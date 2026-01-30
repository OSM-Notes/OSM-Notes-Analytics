-- Creates datamart for countries.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-26

CREATE TABLE IF NOT EXISTS dwh.datamartCountries (
 -- Static values (country name could change)
 dimension_country_id INTEGER, -- The dimension id country.
 country_id INTEGER,
 country_name VARCHAR(100),
 country_name_es VARCHAR(100),
 country_name_en VARCHAR(100),
 iso_alpha2 VARCHAR(2), -- ISO 3166-1 alpha-2 code
 iso_alpha3 VARCHAR(3), -- ISO 3166-1 alpha-3 code
 dimension_continent_id INTEGER, -- Reference to dimension_continents
 date_starting_creating_notes DATE, -- Oldest opened note.
 date_starting_solving_notes DATE, -- Oldest closed note.
 first_open_note_id INTEGER, -- Oldest.
 first_commented_note_id INTEGER,
 first_closed_note_id INTEGER,
 first_reopened_note_id INTEGER,

 -- Dynamic values
 last_year_activity CHAR(371), -- Last year's actions. GitHub tile style.
 latest_open_note_id INTEGER, -- Newest.
 latest_commented_note_id INTEGER,
 latest_closed_note_id INTEGER,
 latest_reopened_note_id INTEGER,
 dates_most_open JSON, -- Dates when most notes were opened.
 dates_most_closed JSON, -- Dates when most notes were closed
 hashtags JSON, -- List of used hashtag.
 users_open_notes JSON, -- List of countries where opening notes.
 users_solving_notes JSON, -- List of countries where closing notes.
 users_open_notes_current_month JSON,
 users_solving_notes_current_month JSON,
 users_open_notes_current_day JSON,
 users_solving_notes_current_day JSON,
 working_hours_of_week_opening JSON, -- Hours when creates notes.
 working_hours_of_week_commenting JSON, -- Hours when comments notes.
 working_hours_of_week_closing JSON, -- Hours when closes notes.
 history_whole_open INTEGER, -- Qty opened notes.
 history_whole_commented INTEGER, -- Qty commented notes.
 history_whole_closed INTEGER, -- Qty closed notes.
 history_whole_closed_with_comment INTEGER, -- Qty closed notes with comments.
 history_whole_reopened INTEGER, -- Qty reopened notes.
 history_year_open INTEGER, -- Qty in the current year.
 history_year_commented INTEGER,
 history_year_closed INTEGER,
 history_year_closed_with_comment INTEGER,
 history_year_reopened INTEGER,
 history_month_open INTEGER, -- Qty in the current month.
 history_month_commented INTEGER,
 history_month_closed INTEGER,
 history_month_closed_with_comment INTEGER,
 history_month_reopened INTEGER,
 history_day_open INTEGER, -- Qty in the current day.
 history_day_commented INTEGER,
 history_day_closed INTEGER,
 history_day_closed_with_comment INTEGER,
 history_day_reopened INTEGER,
 history_2013_open INTEGER, -- Qty in 2013
 history_2013_commented INTEGER,
 history_2013_closed INTEGER,
 history_2013_closed_with_comment INTEGER,
 history_2013_reopened INTEGER,
 ranking_users_opening_2013 JSON,
 ranking_users_closing_2013 JSON,
 json_exported BOOLEAN DEFAULT FALSE,
 avg_days_to_resolution DECIMAL(10,2),
 median_days_to_resolution DECIMAL(10,2),
 notes_resolved_count INTEGER,
 notes_still_open_count INTEGER,
 resolution_rate DECIMAL(5,2),
 applications_used JSON,
 most_used_application_id INTEGER,
 mobile_apps_count INTEGER,
 desktop_apps_count INTEGER,
 avg_comment_length DECIMAL(10,2),
 comments_with_url_count INTEGER,
 comments_with_url_pct DECIMAL(5,2),
 comments_with_mention_count INTEGER,
 comments_with_mention_pct DECIMAL(5,2),
 avg_comments_per_note DECIMAL(10,2),
 active_notes_count INTEGER,
 notes_backlog_size INTEGER,
 notes_age_distribution JSON,
  notes_created_last_30_days INTEGER,
  notes_resolved_last_30_days INTEGER,
  resolution_by_year JSON,
  resolution_by_month JSON,
  hashtags_opening JSON,
  hashtags_resolution JSON,
  hashtags_comments JSON,
  top_opening_hashtag VARCHAR(50),
  top_resolution_hashtag VARCHAR(50),
  opening_hashtag_count INTEGER DEFAULT 0,
  resolution_hashtag_count INTEGER DEFAULT 0,
  application_usage_trends JSON,
  version_adoption_rates JSON,
  notes_health_score DECIMAL(5,2),
  new_vs_resolved_ratio DECIMAL(5,2)
);
COMMENT ON TABLE dwh.datamartCountries IS
  'Contains all precalculated statistical values for countries';
COMMENT ON COLUMN dwh.datamartCountries.dimension_country_id IS
  'Surrogated ID from dimension''country';
COMMENT ON COLUMN dwh.datamartCountries.country_id IS 'OSM country relation id';
COMMENT ON COLUMN dwh.datamartCountries.country_name IS
  'OSM country name in local language';
COMMENT ON COLUMN dwh.datamartCountries.country_name_es IS
  'OSM country name in Spanish';
COMMENT ON COLUMN dwh.datamartCountries.country_name_en IS
  'OSM country name in English';
COMMENT ON COLUMN dwh.datamartCountries.iso_alpha2 IS
  'ISO 3166-1 alpha-2 country code (e.g., US, GB, FR)';
COMMENT ON COLUMN dwh.datamartCountries.iso_alpha3 IS
  'ISO 3166-1 alpha-3 country code (e.g., USA, GBR, FRA)';
COMMENT ON COLUMN dwh.datamartCountries.dimension_continent_id IS
  'Reference to dimension_continents (obtained via dimension_countries.region_id -> dimension_regions.continent_id)';
COMMENT ON COLUMN dwh.datamartCountries.date_starting_creating_notes IS
  'Oldest opened note';
COMMENT ON COLUMN dwh.datamartCountries.date_starting_solving_notes IS
  'Oldest closed note';
COMMENT ON COLUMN dwh.datamartCountries.first_open_note_id IS 'First opened note';
COMMENT ON COLUMN dwh.datamartCountries.first_commented_note_id IS
  'First commented note';
COMMENT ON COLUMN dwh.datamartCountries.first_closed_note_id IS
  'First closed note';
COMMENT ON COLUMN dwh.datamartCountries.first_reopened_note_id IS
  'First reopened note';
COMMENT ON COLUMN dwh.datamartCountries.last_year_activity IS
  'Last year''s actions. GitHub tile style.';
COMMENT ON COLUMN dwh.datamartCountries.latest_open_note_id IS
  'Most recent opened note';
COMMENT ON COLUMN dwh.datamartCountries.latest_commented_note_id IS
  'Most recent commented note';
COMMENT ON COLUMN dwh.datamartCountries.latest_closed_note_id IS
  'Most recent closed note';
COMMENT ON COLUMN dwh.datamartCountries.latest_reopened_note_id IS
  'Most recent reopened note';
COMMENT ON COLUMN dwh.datamartCountries.dates_most_open IS
  'The dates on which the most notes were openen on the country';
COMMENT ON COLUMN dwh.datamartCountries.dates_most_closed IS
  'The dates on which the user closed the most notes';
COMMENT ON COLUMN dwh.datamartCountries.hashtags IS 'List of used hashtag';
COMMENT ON COLUMN dwh.datamartCountries.users_open_notes IS
  'List of users opening notes in the country';
COMMENT ON COLUMN dwh.datamartCountries.users_solving_notes IS
  'List of users closing notes in the country';
COMMENT ON COLUMN dwh.datamartCountries.users_open_notes_current_month IS
  'List of users opening notes in the country in the current month';
COMMENT ON COLUMN dwh.datamartCountries.users_solving_notes_current_month IS
  'List of users closing notes in the country in the current month';
COMMENT ON COLUMN dwh.datamartCountries.users_open_notes_current_day IS
  'List of users opening notes in the country today';
COMMENT ON COLUMN dwh.datamartCountries.users_solving_notes_current_day IS
  'List of users closing notes in the country today';
COMMENT ON COLUMN dwh.datamartCountries.working_hours_of_week_opening IS
  'Hours when the user creates notes';
COMMENT ON COLUMN dwh.datamartCountries.working_hours_of_week_commenting IS
  'Hours when the user comments notes';
COMMENT ON COLUMN dwh.datamartCountries.working_hours_of_week_closing IS
  'Hours when the user closes notes';
COMMENT ON COLUMN dwh.datamartCountries.history_whole_open IS
  'Qty opened notes in the whole history';
COMMENT ON COLUMN dwh.datamartCountries.history_whole_commented IS
  'Qty commented notes in the whole history';
COMMENT ON COLUMN dwh.datamartCountries.history_whole_closed IS
  'Qty closed notes in the whole history';
COMMENT ON COLUMN dwh.datamartCountries.history_whole_closed_with_comment IS
  'Qty closed notes with comments in the whole history';
COMMENT ON COLUMN dwh.datamartCountries.history_whole_reopened IS
  'Qty reopened notes in the whole history';
COMMENT ON COLUMN dwh.datamartCountries.history_year_open IS
  'Qty of notes opened in the current year';
COMMENT ON COLUMN dwh.datamartCountries.history_year_commented IS
  'Qty of notes commented in the current year';
COMMENT ON COLUMN dwh.datamartCountries.history_year_closed IS
  'Qty of notes closed in the current year';
COMMENT ON COLUMN dwh.datamartCountries.history_year_closed_with_comment IS
  'Qty of notes closed with comment in the current year';
COMMENT ON COLUMN dwh.datamartCountries.history_year_reopened IS
  'Qty of notes reopened in the current year';
COMMENT ON COLUMN dwh.datamartCountries.history_month_open IS
  'Qty of notes opened in the current month';
COMMENT ON COLUMN dwh.datamartCountries.history_month_commented IS
  'Qty of notes commented in the current month';
COMMENT ON COLUMN dwh.datamartCountries.history_month_closed IS
  'Qty of notes closed in the current month';
COMMENT ON COLUMN dwh.datamartCountries.history_month_closed_with_comment IS
  'Qty of notes closed with comment in the current month';
COMMENT ON COLUMN dwh.datamartCountries.history_month_reopened IS
  'Qty of notes reopened in the current month';
COMMENT ON COLUMN dwh.datamartCountries.history_day_open IS
  'Qty of notes opened in the current day';
COMMENT ON COLUMN dwh.datamartCountries.history_day_commented IS
  'Qty of notes commented in the current day';
COMMENT ON COLUMN dwh.datamartCountries.history_day_closed IS
  'Qty of notes closed in the current day';
COMMENT ON COLUMN dwh.datamartCountries.history_day_closed_with_comment IS
  'Qty of notes closed with comments in the current day';
COMMENT ON COLUMN dwh.datamartCountries.history_day_reopened IS
  'Qty of notes reopened in the current day';
COMMENT ON COLUMN dwh.datamartCountries.history_2013_open IS
  'Qty of notes opened in 2013';
COMMENT ON COLUMN dwh.datamartCountries.history_2013_commented IS
  'Qty of notes commented in 2013';
COMMENT ON COLUMN dwh.datamartCountries.history_2013_closed IS
  'Qty of notes closed in 2013';
COMMENT ON COLUMN dwh.datamartCountries.history_2013_closed_with_comment IS
  'Qty of notes closed with comment in 2013';
COMMENT ON COLUMN dwh.datamartCountries.history_2013_reopened IS
  'Qty of notes reopened in 2013';
COMMENT ON COLUMN dwh.datamartCountries.ranking_users_opening_2013 IS
  'Ranking of users creating notes on year 2013';
COMMENT ON COLUMN dwh.datamartCountries.ranking_users_closing_2013 IS
  'Ranking of users closing notes on year 2013';
COMMENT ON COLUMN dwh.datamartCountries.json_exported IS
  'Flag indicating if country data has been exported to JSON';
COMMENT ON COLUMN dwh.datamartCountries.avg_days_to_resolution IS
  'Average days to resolve notes (from open to most recent close)';
COMMENT ON COLUMN dwh.datamartCountries.median_days_to_resolution IS
  'Median days to resolve notes (from open to most recent close)';
COMMENT ON COLUMN dwh.datamartCountries.notes_resolved_count IS
  'Number of notes that have been closed';
COMMENT ON COLUMN dwh.datamartCountries.notes_still_open_count IS
  'Number of notes opened but never closed';
COMMENT ON COLUMN dwh.datamartCountries.resolution_rate IS
  'Percentage of notes resolved (closed/total opened)';
COMMENT ON COLUMN dwh.datamartCountries.applications_used IS
  'JSON array of applications used to create notes in this country';
COMMENT ON COLUMN dwh.datamartCountries.most_used_application_id IS
  'ID of the most used application for creating notes';
COMMENT ON COLUMN dwh.datamartCountries.mobile_apps_count IS
  'Number of mobile applications used';
COMMENT ON COLUMN dwh.datamartCountries.desktop_apps_count IS
  'Number of desktop/web applications used';
COMMENT ON COLUMN dwh.datamartCountries.avg_comment_length IS
  'Average length of comments in characters';
COMMENT ON COLUMN dwh.datamartCountries.comments_with_url_count IS
  'Number of comments containing URLs';
COMMENT ON COLUMN dwh.datamartCountries.comments_with_url_pct IS
  'Percentage of comments containing URLs';
COMMENT ON COLUMN dwh.datamartCountries.comments_with_mention_count IS
  'Number of comments containing mentions';
COMMENT ON COLUMN dwh.datamartCountries.comments_with_mention_pct IS
  'Percentage of comments containing mentions';
COMMENT ON COLUMN dwh.datamartCountries.avg_comments_per_note IS
  'Average number of comments per note';
COMMENT ON COLUMN dwh.datamartCountries.active_notes_count IS
  'Number of notes currently open in this country';
COMMENT ON COLUMN dwh.datamartCountries.notes_backlog_size IS
  'Number of notes opened but not yet resolved';
COMMENT ON COLUMN dwh.datamartCountries.notes_age_distribution IS
  'JSON distribution of note ages (0-7 days, 8-30 days, 31-90 days, 90+ days)';
COMMENT ON COLUMN dwh.datamartCountries.notes_created_last_30_days IS
  'Number of notes created in the last 30 days';
COMMENT ON COLUMN dwh.datamartCountries.notes_resolved_last_30_days IS
  'Number of notes resolved in the last 30 days';
COMMENT ON COLUMN dwh.datamartCountries.resolution_by_year IS
  'JSON array of resolution metrics by year: [{year, avg_days, median_days, resolution_rate}]';
COMMENT ON COLUMN dwh.datamartCountries.resolution_by_month IS
  'JSON array of resolution metrics by month: [{year, month, avg_days, median_days, resolution_rate}]';
COMMENT ON COLUMN dwh.datamartCountries.hashtags_opening IS 'Top hashtags used in note opening actions';
COMMENT ON COLUMN dwh.datamartCountries.hashtags_resolution IS 'Top hashtags used in note resolution actions';
COMMENT ON COLUMN dwh.datamartCountries.hashtags_comments IS 'Top hashtags used in comment actions';
COMMENT ON COLUMN dwh.datamartCountries.top_opening_hashtag IS 'Most frequently used opening hashtag';
COMMENT ON COLUMN dwh.datamartCountries.top_resolution_hashtag IS 'Most frequently used resolution hashtag';
COMMENT ON COLUMN dwh.datamartCountries.opening_hashtag_count IS 'Total count of opening hashtags used';
COMMENT ON COLUMN dwh.datamartCountries.resolution_hashtag_count IS 'Total count of resolution hashtags used';
COMMENT ON COLUMN dwh.datamartCountries.application_usage_trends IS 'JSON array of application usage trends by year: [{year, app_id, app_name, count, pct}]';
COMMENT ON COLUMN dwh.datamartCountries.version_adoption_rates IS 'JSON array of version adoption rates by year: [{year, version, count, adoption_rate}]';
COMMENT ON COLUMN dwh.datamartCountries.notes_health_score IS 'Overall notes health score (0-100) based on resolution rate, backlog size, and age distribution';
COMMENT ON COLUMN dwh.datamartCountries.new_vs_resolved_ratio IS 'Ratio of new notes created vs resolved notes (last 30 days)';

CREATE TABLE IF NOT EXISTS dwh.max_date_countries_processed (
  date date NOT NULL
);
COMMENT ON TABLE dwh.max_date_countries_processed IS
  'Max date for countries processed, to move the activities';
COMMENT ON COLUMN dwh.max_date_countries_processed.date IS
  'Value of the max date of countries processed';

-- Primary keys.
ALTER TABLE dwh.datamartCountries
ADD CONSTRAINT pk_datamartCountries
PRIMARY KEY (dimension_country_id);

-- Processes all countries.
UPDATE /* Notes-ETL */ dwh.dimension_countries
SET modified = TRUE;
