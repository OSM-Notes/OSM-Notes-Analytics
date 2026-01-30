-- Creates datamart for global statistics.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-12-20

CREATE TABLE IF NOT EXISTS dwh.datamartGlobal (
 -- Static values
 dimension_global_id INTEGER DEFAULT 1, -- Single global record
 date_starting_creating_notes DATE, -- Oldest opened note globally
 date_starting_solving_notes DATE, -- Oldest closed note globally
 first_open_note_id INTEGER, -- Oldest opened note
 first_closed_note_id INTEGER, -- Oldest closed note
 first_reopened_note_id INTEGER, -- Oldest reopened note

 -- Dynamic values
 last_year_activity CHAR(371), -- Last year's actions. GitHub tile style.
 latest_open_note_id INTEGER, -- Newest opened note
 latest_closed_note_id INTEGER, -- Newest closed note
 latest_reopened_note_id INTEGER, -- Newest reopened note

 -- Historical totals
 history_whole_open INTEGER, -- Total opened notes in history
 history_whole_commented INTEGER, -- Total commented notes in history
 history_whole_closed INTEGER, -- Total closed notes in history
 history_whole_closed_with_comment INTEGER, -- Total closed with comment
 history_whole_reopened INTEGER, -- Total reopened notes in history

 -- Current year totals
 history_year_open INTEGER, -- Notes opened in current year
 history_year_commented INTEGER, -- Notes commented in current year
 history_year_closed INTEGER, -- Notes closed in current year
 history_year_closed_with_comment INTEGER, -- Notes closed with comment in current year
 history_year_reopened INTEGER, -- Notes reopened in current year

 -- Current status
 currently_open_count INTEGER, -- Notes currently open
 currently_closed_count INTEGER, -- Notes currently closed (never reopened)
 notes_created_last_30_days INTEGER, -- Notes created in last 30 days
 notes_resolved_last_30_days INTEGER, -- Notes resolved in last 30 days
 notes_backlog_size INTEGER, -- Open notes older than 7 days

 -- Resolution metrics
 avg_days_to_resolution DECIMAL(10,2), -- Average days to resolve (all time)
 median_days_to_resolution DECIMAL(10,2), -- Median days to resolve (all time)
 avg_days_to_resolution_current_year DECIMAL(10,2), -- Average days to resolve for notes created this year
 median_days_to_resolution_current_year DECIMAL(10,2), -- Median days to resolve for notes created this year
 notes_resolved_count INTEGER, -- Total notes that have been resolved
 resolution_rate DECIMAL(5,2), -- Percentage of resolved notes

 -- Additional metrics
 active_users_count INTEGER, -- Users with at least one action in last 30 days
 notes_age_distribution JSON, -- Distribution of note ages
 top_countries JSON, -- Top countries by note activity
 applications_used JSON, -- Most used applications
 most_used_application_id INTEGER, -- ID of most used application
 mobile_apps_count INTEGER, -- Number of mobile applications
 desktop_apps_count INTEGER, -- Number of desktop/web applications
 avg_comment_length DECIMAL(10,2), -- Average comment length
 comments_with_url_pct DECIMAL(5,2), -- Percentage of comments with URLs
 comments_with_mention_pct DECIMAL(5,2), -- Percentage of comments with mentions
 avg_comments_per_note DECIMAL(10,2) -- Average comments per note
);

COMMENT ON TABLE dwh.datamartGlobal IS
  'Contains all precalculated global statistical values for all notes';
COMMENT ON COLUMN dwh.datamartGlobal.dimension_global_id IS
  'Always 1, single record for global stats';
COMMENT ON COLUMN dwh.datamartGlobal.date_starting_creating_notes IS
  'Date of oldest opened note globally';
COMMENT ON COLUMN dwh.datamartGlobal.date_starting_solving_notes IS
  'Date of oldest closed note globally';
COMMENT ON COLUMN dwh.datamartGlobal.first_open_note_id IS 'First opened note globally';
COMMENT ON COLUMN dwh.datamartGlobal.first_closed_note_id IS 'First closed note globally';
COMMENT ON COLUMN dwh.datamartGlobal.first_reopened_note_id IS 'First reopened note globally';
COMMENT ON COLUMN dwh.datamartGlobal.last_year_activity IS
  'Last year''s actions. GitHub tile style.';
COMMENT ON COLUMN dwh.datamartGlobal.latest_open_note_id IS 'Most recent opened note';
COMMENT ON COLUMN dwh.datamartGlobal.latest_closed_note_id IS 'Most recent closed note';
COMMENT ON COLUMN dwh.datamartGlobal.latest_reopened_note_id IS 'Most recent reopened note';
COMMENT ON COLUMN dwh.datamartGlobal.history_whole_open IS
  'Total opened notes in the whole history';
COMMENT ON COLUMN dwh.datamartGlobal.history_whole_commented IS
  'Total commented notes in the whole history';
COMMENT ON COLUMN dwh.datamartGlobal.history_whole_closed IS
  'Total closed notes in the whole history';
COMMENT ON COLUMN dwh.datamartGlobal.history_whole_closed_with_comment IS
  'Total closed notes with comments in the whole history';
COMMENT ON COLUMN dwh.datamartGlobal.history_whole_reopened IS
  'Total reopened notes in the whole history';
COMMENT ON COLUMN dwh.datamartGlobal.history_year_open IS
  'Number of notes opened in the current year';
COMMENT ON COLUMN dwh.datamartGlobal.history_year_commented IS
  'Number of notes commented in the current year';
COMMENT ON COLUMN dwh.datamartGlobal.history_year_closed IS
  'Number of notes closed in the current year';
COMMENT ON COLUMN dwh.datamartGlobal.history_year_closed_with_comment IS
  'Number of notes closed with comment in the current year';
COMMENT ON COLUMN dwh.datamartGlobal.history_year_reopened IS
  'Number of notes reopened in the current year';
COMMENT ON COLUMN dwh.datamartGlobal.currently_open_count IS
  'Number of notes currently open';
COMMENT ON COLUMN dwh.datamartGlobal.currently_closed_count IS
  'Number of notes currently closed (never reopened)';
COMMENT ON COLUMN dwh.datamartGlobal.notes_created_last_30_days IS
  'Number of notes created in the last 30 days';
COMMENT ON COLUMN dwh.datamartGlobal.notes_resolved_last_30_days IS
  'Number of notes resolved in the last 30 days';
COMMENT ON COLUMN dwh.datamartGlobal.notes_backlog_size IS
  'Number of open notes older than 7 days';
COMMENT ON COLUMN dwh.datamartGlobal.avg_days_to_resolution IS
  'Average days to resolve notes globally (all time)';
COMMENT ON COLUMN dwh.datamartGlobal.median_days_to_resolution IS
  'Median days to resolve notes globally (all time)';
COMMENT ON COLUMN dwh.datamartGlobal.avg_days_to_resolution_current_year IS
  'Average days to resolve notes created this year';
COMMENT ON COLUMN dwh.datamartGlobal.median_days_to_resolution_current_year IS
  'Median days to resolve notes created this year';
COMMENT ON COLUMN dwh.datamartGlobal.notes_resolved_count IS
  'Total number of notes that have been resolved';
COMMENT ON COLUMN dwh.datamartGlobal.resolution_rate IS
  'Percentage of notes resolved (closed/total opened)';
COMMENT ON COLUMN dwh.datamartGlobal.active_users_count IS
  'Number of users with at least one action in last 30 days';
COMMENT ON COLUMN dwh.datamartGlobal.notes_age_distribution IS
  'JSON distribution of note ages (0-7 days, 8-30 days, 31-90 days, 90+ days)';
COMMENT ON COLUMN dwh.datamartGlobal.top_countries IS
  'JSON array of top countries by note activity';
COMMENT ON COLUMN dwh.datamartGlobal.applications_used IS
  'JSON array of most used applications';
COMMENT ON COLUMN dwh.datamartGlobal.most_used_application_id IS
  'ID of the most used application';
COMMENT ON COLUMN dwh.datamartGlobal.mobile_apps_count IS
  'Number of mobile applications used';
COMMENT ON COLUMN dwh.datamartGlobal.desktop_apps_count IS
  'Number of desktop/web applications used';
COMMENT ON COLUMN dwh.datamartGlobal.avg_comment_length IS
  'Average length of comments in characters';
COMMENT ON COLUMN dwh.datamartGlobal.comments_with_url_pct IS
  'Percentage of comments containing URLs';
COMMENT ON COLUMN dwh.datamartGlobal.comments_with_mention_pct IS
  'Percentage of comments containing mentions';
COMMENT ON COLUMN dwh.datamartGlobal.avg_comments_per_note IS
  'Average number of comments per note';

CREATE TABLE IF NOT EXISTS dwh.max_date_global_processed (
  date date NOT NULL
);
COMMENT ON TABLE dwh.max_date_global_processed IS
  'Max date for global processed, to move the activities';
COMMENT ON COLUMN dwh.max_date_global_processed.date IS
  'Value of the max date of global processed';

-- Primary key (with check and error handling)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'pk_datamartGlobal'
    AND table_schema = 'dwh'
    AND table_name = 'datamartGlobal'
  ) THEN
    BEGIN
      ALTER TABLE dwh.datamartGlobal
       ADD CONSTRAINT pk_datamartGlobal
       PRIMARY KEY (dimension_global_id);
    EXCEPTION
      WHEN OTHERS THEN
        -- Constraint already exists or other error, ignore
        NULL;
    END;
  END IF;
END $$;

-- Ensure only one record exists
INSERT INTO dwh.datamartGlobal (dimension_global_id)
SELECT 1
WHERE NOT EXISTS (SELECT 1 FROM dwh.datamartGlobal WHERE dimension_global_id = 1);


