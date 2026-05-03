-- Export closed notes by country to CSV
-- This query exports closed notes with all relevant information for AI context
-- Comments are cleaned: multiple lines converted to spaces, quotes normalized,
-- length limited
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-01-17
--
-- Performance optimizations:
-- - Eliminated correlated subqueries using aggregations and window functions
-- - Removed duplicate logic for finding latest close
-- - Optimized JOINs with FDW tables using LATERAL JOINs
-- - Pre-aggregated comment counts and reopen status
--
-- Column order optimized for AI context:
-- 1. Basic info: note_id, country, location, dates
-- 2. Problem: opening_comment (what was reported)
-- 3. Solution: closing_comment (how it was resolved), who closed it
-- 4. Context: resolution time, comment count, reopen status
--
-- Columns exported:
-- - note_id: OSM note ID
-- - country_name: Country name
-- - latitude: Note latitude
-- - longitude: Note longitude
-- - opened_at: Date and time when note was opened
-- - closed_at: Date and time when note was closed
-- - days_to_resolution: Days from open to close
-- - opened_by_username: Username who opened the note
-- - opening_comment: Initial comment (cleaned, max 2000 chars)
-- - total_comments: Total number of comments on the note
-- - was_reopened: Whether note was reopened before final close (0/1)
-- - closed_by_username: Username who closed the note
-- - closing_comment: Comment when note was closed (cleaned, max 2000 chars)
--
-- Usage:
--   This SQL is used by bin/dwh/exportAndPushCSVToGitHub.sh
--   The script replaces :country_id and :max_notes_per_country with actual
--   values before execution
--   :country_id - Country ID to export
--   :max_notes_per_country - Maximum number of notes to export
--                            (default: 400000)
--                            This limits export to most recent notes to keep
--                            files under 100MB

\set ON_ERROR_STOP on

-- Set default for max_notes_per_country if not provided
\if :{?max_notes_per_country}
\else
\set max_notes_per_country 400000
\endif

-- Helper function to clean comment text for CSV export
-- - Replaces multiple newlines/tabs with single space
-- - Converts double quotes to single quotes
-- - Truncates to max length (2000 chars)
-- - Removes leading/trailing whitespace
CREATE OR REPLACE FUNCTION dwh.clean_comment_for_csv(comment_text TEXT)
RETURNS TEXT AS $$
BEGIN
  RETURN LEFT(
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          COALESCE(comment_text, ''),
          E'[\\n\\r\\t]+', ' ', 'g'  -- Replace newlines/tabs with space
        ),
        '"', '''', 'g'  -- Replace double quotes with single quotes
      )
    ),
    2000  -- Limit to 2000 characters
  );
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Step 0: Get dimension_country_id first to enable better partition pruning
-- This allows PostgreSQL to use partition indexes more efficiently
WITH country_dimension AS (
    SELECT dimension_country_id
    FROM dwh.dimension_countries
    WHERE country_id = :country_id
),

-- Step 1: Get the most recent close fact for each note in the country
-- Filter by dimension_id_country directly to enable partition pruning
-- Limit to most recent notes for AI context
-- (configurable via :max_notes_per_country)
latest_closes AS (
    SELECT DISTINCT ON (f.id_note)
        f.fact_id,
        f.id_note,
        f.action_at,
        f.days_to_resolution,
        f.dimension_id_country,
        f.opened_dimension_id_date,
        f.opened_dimension_id_user,
        f.closed_dimension_id_user
    FROM dwh.facts f
        CROSS JOIN country_dimension cd
    WHERE f.action_comment = 'closed'
        AND f.dimension_id_country = cd.dimension_country_id
    ORDER BY f.id_note ASC, f.fact_id DESC
),

-- Step 1b: Limit to most recent notes (for AI context, we prioritize recent
-- resolutions)
-- This ensures we export the most relevant examples for AI training
-- Recent notes are more valuable for AI context as they reflect current
-- resolution patterns
limited_closes AS (
    SELECT *
    FROM latest_closes
    ORDER BY action_at DESC  -- noqa: PRS
    LIMIT :max_notes_per_country
),

-- Step 2: Pre-aggregate comment counts and reopen status for limited notes
-- This eliminates correlated subqueries in the main query
note_metrics AS (
    SELECT
        f.id_note,
        COUNT(*) FILTER (
            WHERE f.action_comment IN (
                'commented', 'opened', 'closed', 'reopened'
            )
        ) AS total_comments,
        MAX(CASE WHEN f.action_comment = 'reopened' THEN 1 ELSE 0 END)
        AS was_reopened
    FROM dwh.facts f
        JOIN limited_closes lc
            ON f.id_note = lc.id_note
    GROUP BY f.id_note
),

-- Step 3: Get opening and closing comments using LATERAL JOINs for better
-- performance
-- LATERAL JOINs allow the optimizer to push filters down to the FDW queries
comments_data AS (
    SELECT
        lc.id_note,
        -- Get opening comment (first opened event)
        opening_comment.body AS opening_body,
        -- Get closing comment (last closed event for this note)
        closing_comment.body AS closing_body
    FROM limited_closes lc
        -- LATERAL JOIN for opening comment - only fetches one row per note
        LEFT JOIN LATERAL (
            SELECT nct.body
            FROM public.note_comments nc
                JOIN public.note_comments_text nct
                    ON nc.note_id = nct.note_id
                        AND nc.sequence_action = nct.sequence_action
            WHERE nc.note_id = lc.id_note
                AND nc.event = 'opened'
            ORDER BY nc.sequence_action ASC
            LIMIT 1
        ) opening_comment ON TRUE
        -- LATERAL JOIN for closing comment - only fetches one row per note
        LEFT JOIN LATERAL (
            SELECT nct.body
            FROM public.note_comments nc
                JOIN public.note_comments_text nct
                    ON nc.note_id = nct.note_id
                        AND nc.sequence_action = nct.sequence_action
            WHERE nc.note_id = lc.id_note
                AND nc.event = 'closed'
            ORDER BY nc.sequence_action DESC
            LIMIT 1
        ) closing_comment ON TRUE
)

-- Main query with cleaned comments and optimized column order for AI context
SELECT
    -- 1. Basic identification and location
    lc.id_note AS note_id,
    COALESCE(dc.country_name, dc.country_name_en, 'Unknown') AS country_name,
    n.latitude,
    n.longitude,
    -- 2. Timeline
    -- Get opened_at from dimension_days using opened_dimension_id_date
    TO_CHAR(opened_date.date_id, 'YYYY-MM-DD HH24:MI:SS') AS opened_at,
    TO_CHAR(lc.action_at, 'YYYY-MM-DD HH24:MI:SS') AS closed_at,
    COALESCE(lc.days_to_resolution, 0) AS days_to_resolution,
    -- 3. Problem context (what was reported)
    COALESCE(u_opened.username, 'Unknown') AS opened_by_username,
    COALESCE(
        dwh.clean_comment_for_csv(cd.opening_body), ''
    ) AS opening_comment,
    COALESCE(nm.total_comments, 0) AS total_comments,
    COALESCE(nm.was_reopened, 0) AS was_reopened,
    -- 4. Solution context (how it was resolved)
    COALESCE(u_closed.username, 'Unknown') AS closed_by_username,
    COALESCE(
        dwh.clean_comment_for_csv(cd.closing_body), ''
    ) AS closing_comment
FROM limited_closes lc
    -- Get cleaned comments and metadata
    JOIN comments_data cd
        ON lc.id_note = cd.id_note
    -- Get pre-aggregated metrics
    LEFT JOIN note_metrics nm
        ON lc.id_note = nm.id_note
    -- Get country information
    JOIN dwh.dimension_countries dc
        ON lc.dimension_id_country = dc.dimension_country_id
    -- Get note coordinates
    LEFT JOIN public.notes n
        ON lc.id_note = n.note_id
    -- Get opened date from dimension_days
    LEFT JOIN dwh.dimension_days opened_date
        ON lc.opened_dimension_id_date = opened_date.dimension_day_id
    -- Get user who opened the note
    LEFT JOIN dwh.dimension_users du_opened
        ON lc.opened_dimension_id_user = du_opened.dimension_user_id
    LEFT JOIN public.users u_opened
        ON du_opened.user_id = u_opened.user_id
    -- Get user who closed the note
    LEFT JOIN dwh.dimension_users du_closed
        ON lc.closed_dimension_id_user = du_closed.dimension_user_id
    LEFT JOIN public.users u_closed
        ON du_closed.user_id = u_closed.user_id
ORDER BY
    COALESCE(dc.country_name, dc.country_name_en, 'Unknown'),
    lc.action_at DESC;

-- Note: The helper function dwh.clean_comment_for_csv() is kept for reuse
-- in other export queries
