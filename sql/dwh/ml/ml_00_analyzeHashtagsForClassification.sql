-- Analysis of hashtags for note classification
-- This script analyzes existing hashtags in the DWH to identify
-- patterns that could be used for classification
--
-- Author: OSM Notes Analytics Project
-- Date: 2025-12-20
-- Purpose: Support ML classification by analyzing hashtag patterns

-- ============================================================================
-- 1. Most Common Hashtags
-- ============================================================================
-- Find the most frequently used hashtags
-- These could indicate common note categories

SELECT
  h.hashtag_name,
  COUNT(DISTINCT fh.fact_id) AS usage_count,
  COUNT(DISTINCT f.id_note) AS notes_count,
  COUNT(DISTINCT f.dimension_id_country) AS countries_count,
  ROUND(COUNT(DISTINCT fh.fact_id)::DECIMAL
        / (SELECT COUNT(DISTINCT fact_id) FROM dwh.fact_hashtags) * 100, 2) AS usage_percentage
FROM dwh.fact_hashtags fh
JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
JOIN dwh.facts f ON fh.fact_id = f.fact_id
WHERE f.action_comment = 'opened'  -- Only opening actions
GROUP BY h.hashtag_name
ORDER BY usage_count DESC
LIMIT 100;

-- ============================================================================
-- 2. Hashtags by Note Outcome
-- ============================================================================
-- Analyze which hashtags are associated with processed vs closed notes
-- This helps identify hashtags that indicate actionable notes

WITH note_outcomes AS (
  SELECT
    f.id_note,
    CASE
      WHEN f.closed_dimension_id_date IS NOT NULL
           AND (SELECT COUNT(*)
            FROM dwh.facts f2
            WHERE f2.id_note = f.id_note
              AND f2.action_comment = 'commented'
              AND f2.action_at < (
                SELECT MIN(fc.action_at)
                FROM dwh.facts fc
                WHERE fc.id_note = f.id_note
                  AND fc.action_comment = 'closed'
                  AND fc.action_at > f.action_at
              )) > 0
      THEN 'processed'
      WHEN f.closed_dimension_id_date IS NOT NULL
      THEN 'closed'
      ELSE 'open'
    END AS outcome
  FROM dwh.facts f
  WHERE f.action_comment = 'opened'
)

SELECT
  h.hashtag_name,
  no.outcome,
  COUNT(DISTINCT f.id_note) AS notes_count,
  ROUND(AVG(f.days_to_resolution), 2) AS avg_resolution_days
FROM dwh.facts f
JOIN note_outcomes no ON f.id_note = no.id_note
JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
WHERE f.action_comment = 'opened'
GROUP BY h.hashtag_name, no.outcome
ORDER BY h.hashtag_name ASC, notes_count DESC;

-- ============================================================================
-- 3. Hashtag Categories (Potential Classification)
-- ============================================================================
-- Identify hashtags that might indicate specific note types
-- Based on common patterns and keywords

SELECT
  h.hashtag_name,
  CASE
    -- Fire/emergency related
    WHEN LOWER(h.hashtag_name) LIKE '%fire%'
         OR LOWER(h.hashtag_name) LIKE '%bomber%'
         OR LOWER(h.hashtag_name) LIKE '%emergency%' THEN 'firefighter'

    -- Transportation/airplane related
    WHEN LOWER(h.hashtag_name) LIKE '%air%'
         OR LOWER(h.hashtag_name) LIKE '%plane%'
         OR LOWER(h.hashtag_name) LIKE '%avion%' THEN 'airplane'

    -- Accessibility related
    WHEN LOWER(h.hashtag_name) LIKE '%wheel%'
         OR LOWER(h.hashtag_name) LIKE '%access%'
         OR LOWER(h.hashtag_name) LIKE '%silla%' THEN 'wheelchair'

    -- Campaign related
    WHEN LOWER(h.hashtag_name) LIKE '%missing%'
         OR LOWER(h.hashtag_name) LIKE '%map%'
         OR LOWER(h.hashtag_name) LIKE '%campaign%' THEN 'campaign'

    -- Fix/correction related
    WHEN LOWER(h.hashtag_name) LIKE '%fix%'
         OR LOWER(h.hashtag_name) LIKE '%correc%'
         OR LOWER(h.hashtag_name) LIKE '%error%' THEN 'correction'

    -- Other categories can be added here
    ELSE 'other'
  END AS potential_category,
  COUNT(DISTINCT f.id_note) AS notes_count
FROM dwh.facts f
JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
WHERE f.action_comment = 'opened'
GROUP BY h.hashtag_name, potential_category
HAVING potential_category != 'other'
ORDER BY potential_category ASC, notes_count DESC;

-- ============================================================================
-- 4. Hashtags by Application
-- ============================================================================
-- See which applications generate notes with which hashtags
-- This helps understand note type patterns by application

SELECT
  a.application_name,
  h.hashtag_name,
  COUNT(DISTINCT f.id_note) AS notes_count,
  ROUND(COUNT(DISTINCT f.id_note)::DECIMAL
        / (SELECT COUNT(DISTINCT f2.id_note)
         FROM dwh.facts f2
         WHERE f2.dimension_application_creation = f.dimension_application_creation
           AND f2.action_comment = 'opened') * 100, 2) AS percentage_of_app_notes
FROM dwh.facts f
JOIN dwh.dimension_applications a ON f.dimension_application_creation = a.dimension_application_id
JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
WHERE f.action_comment = 'opened'
  AND f.dimension_application_creation IS NOT NULL
GROUP BY a.application_name, h.hashtag_name
HAVING COUNT(DISTINCT f.id_note) >= 5  -- Only significant hashtags
ORDER BY a.application_name ASC, notes_count DESC;

-- ============================================================================
-- 5. Hashtag Co-occurrence
-- ============================================================================
-- Find hashtags that often appear together
-- This can help identify note type patterns

WITH note_hashtags AS (
  SELECT
    f.id_note,
    h.hashtag_name
  FROM dwh.facts f
  JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
  JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
  WHERE f.action_comment = 'opened'
)

SELECT
  h1.hashtag_name AS hashtag1,
  h2.hashtag_name AS hashtag2,
  COUNT(DISTINCT h1.id_note) AS co_occurrence_count
FROM note_hashtags h1
JOIN note_hashtags h2
  ON h1.id_note = h2.id_note
  AND h1.hashtag_name < h2.hashtag_name  -- Avoid duplicates and self-pairs
GROUP BY h1.hashtag_name, h2.hashtag_name
HAVING COUNT(DISTINCT h1.id_note) >= 3  -- Only significant co-occurrences
ORDER BY co_occurrence_count DESC
LIMIT 50;

-- ============================================================================
-- 6. Hashtags for ML Feature Engineering
-- ============================================================================
-- NOTE: Same view is created by ml_01_setupPgML.sql for standalone ML setup.

CREATE OR REPLACE VIEW dwh.v_note_hashtag_features AS
SELECT
  f.id_note,
  f.opened_dimension_id_date,
  COUNT(DISTINCT fh.dimension_hashtag_id) AS hashtag_count,
  ARRAY_AGG(DISTINCT h.hashtag_name ORDER BY h.hashtag_name) AS hashtag_names,
  -- Category indicators (can be expanded)
  BOOLEAN_OR(LOWER(h.hashtag_name) LIKE '%fire%'
             OR LOWER(h.hashtag_name) LIKE '%bomber%') AS has_fire_keyword,
  BOOLEAN_OR(LOWER(h.hashtag_name) LIKE '%air%'
             OR LOWER(h.hashtag_name) LIKE '%plane%') AS has_air_keyword,
  BOOLEAN_OR(LOWER(h.hashtag_name) LIKE '%wheel%'
             OR LOWER(h.hashtag_name) LIKE '%access%') AS has_access_keyword,
  BOOLEAN_OR(LOWER(h.hashtag_name) LIKE '%missing%'
             OR LOWER(h.hashtag_name) LIKE '%campaign%') AS has_campaign_keyword,
  BOOLEAN_OR(LOWER(h.hashtag_name) LIKE '%fix%'
             OR LOWER(h.hashtag_name) LIKE '%correc%') AS has_fix_keyword
FROM dwh.facts f
LEFT JOIN dwh.fact_hashtags fh ON f.fact_id = fh.fact_id
LEFT JOIN dwh.dimension_hashtags h ON fh.dimension_hashtag_id = h.dimension_hashtag_id
WHERE f.action_comment = 'opened'
GROUP BY f.id_note, f.opened_dimension_id_date;

COMMENT ON VIEW dwh.v_note_hashtag_features IS
  'Hashtag-based features for ML classification. Includes hashtag count, names, and category indicators.';

-- ============================================================================
-- Usage Examples
-- ============================================================================

-- Example 1: Get hashtag features for a specific note
-- SELECT * FROM dwh.v_note_hashtag_features WHERE id_note = 12345;

-- Example 2: Find notes with specific hashtag categories
-- SELECT * FROM dwh.v_note_hashtag_features
-- WHERE has_fire_keyword = TRUE OR has_air_keyword = TRUE;

-- Example 3: Join with other features for ML
-- SELECT
--   f.id_note,
--   f.comment_length,
--   f.has_url,
--   nhf.hashtag_count,
--   nhf.has_fire_keyword,
--   nhf.has_air_keyword
-- FROM dwh.facts f
-- JOIN dwh.v_note_hashtag_features nhf ON f.id_note = nhf.id_note
-- WHERE f.action_comment = 'opened';
