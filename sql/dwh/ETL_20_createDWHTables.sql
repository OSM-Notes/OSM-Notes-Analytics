-- Create data warehouse tables.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-24

CREATE SCHEMA IF NOT EXISTS dwh;
COMMENT ON SCHEMA dwh IS
  'Data warehouse objects';

-- Create note_event_enum type if it doesn't exist
-- FIXED: Changed from CREATE TYPE IF NOT EXISTS (not supported in older PostgreSQL)
--        to DO block that checks for existence first
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'note_event_enum') THEN
    CREATE TYPE note_event_enum AS ENUM (
      'opened',
      'closed',
      'commented',
      'reopened',
      'hidden'
    );
  END IF;
END
$$;
COMMENT ON TYPE note_event_enum IS
  'Types of events that can occur on an OSM note';

CREATE TABLE dwh.facts (
 fact_id BIGSERIAL,
 id_note INTEGER NOT NULL,
 sequence_action INTEGER,
 dimension_id_country INTEGER NOT NULL,
 processing_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
 action_at TIMESTAMP NOT NULL,
 action_comment note_event_enum NOT NULL,
 action_dimension_id_date INTEGER NOT NULL,
 action_dimension_id_hour_of_week SMALLINT NOT NULL,
 action_dimension_id_user INTEGER,
 opened_dimension_id_date INTEGER NOT NULL,
 opened_dimension_id_hour_of_week SMALLINT NOT NULL,
 opened_dimension_id_user INTEGER,
 closed_dimension_id_date INTEGER,
 closed_dimension_id_hour_of_week SMALLINT,
 closed_dimension_id_user INTEGER,
 dimension_application_creation INTEGER,
  dimension_application_version INTEGER,
 recent_opened_dimension_id_date INTEGER, -- Later converted to NOT NULL
 days_to_resolution INTEGER,
 days_to_resolution_active INTEGER,
 days_to_resolution_from_reopen INTEGER,
 hashtag_number INTEGER,
 -- Local time support
 action_timezone_id INTEGER,
 local_action_dimension_id_date INTEGER,
 local_action_dimension_id_hour_of_week SMALLINT,
 -- Season analysis
 action_dimension_id_season SMALLINT,
 -- Comment metrics
 comment_length INTEGER,
 has_url BOOLEAN DEFAULT FALSE,
 has_mention BOOLEAN DEFAULT FALSE,
 -- Note activity metrics (PERFORMANCE WARNING: Trigger calculates these)
 total_comments_on_note INTEGER,
 total_reopenings_count INTEGER,
 total_actions_on_note INTEGER
) PARTITION BY RANGE (action_at);
-- Note: Any new column should be included in:
-- staging.process_notes_at_date_${YEAR} (initialFactsLoadCreate)
-- staging.process_notes_at_date (createStagingObjects)
-- ETL.sh > __initialFacts
--
-- IMPORTANT: dwh.facts is PARTITIONED by action_at (year).
-- Partitions are created by ETL_21_createFactPartitions.sql
-- To add a new year partition, simply run that script again.
COMMENT ON TABLE dwh.facts IS
  'Facts table (partitioned by action_at year), center of the star schema';
COMMENT ON COLUMN dwh.facts.fact_id IS 'Surrogated ID';
COMMENT ON COLUMN dwh.facts.id_note IS 'OSM note id';
COMMENT ON COLUMN dwh.facts.sequence_action IS 'Creation sequence';
COMMENT ON COLUMN dwh.facts.dimension_id_country IS 'OSM country relation id';
COMMENT ON COLUMN dwh.facts.processing_time IS
  'Timestamp when the comment was processed';
COMMENT ON COLUMN dwh.facts.action_at IS
 'Timestamp when the action took place';
COMMENT ON COLUMN dwh.facts.action_comment IS 'Type of comment action';
COMMENT ON COLUMN dwh.facts.action_dimension_id_date IS 'Date of the action';
COMMENT ON COLUMN dwh.facts.action_dimension_id_hour_of_week IS
  'Hour of the week action';
COMMENT ON COLUMN dwh.facts.action_dimension_id_user IS
  'User who performed the action';
COMMENT ON COLUMN dwh.facts.opened_dimension_id_date IS
  'Date when the note was created';
COMMENT ON COLUMN dwh.facts.opened_dimension_id_hour_of_week IS
  'Hour of the week when the note was created';
COMMENT ON COLUMN dwh.facts.opened_dimension_id_user IS
  'User who created the note. It could be annonymous';
COMMENT ON COLUMN dwh.facts.closed_dimension_id_date IS
  'Date when the note was closed';
COMMENT ON COLUMN dwh.facts.closed_dimension_id_hour_of_week IS
  'Hour of the week when the note was closed';
COMMENT ON COLUMN dwh.facts.closed_dimension_id_user IS
  'User who created the note';
COMMENT ON COLUMN dwh.facts.dimension_application_creation IS
  'Application used to create the note. Only for opened actions';
COMMENT ON COLUMN dwh.facts.dimension_application_version IS
  'Version of the application used to create the note';
COMMENT ON COLUMN dwh.facts.recent_opened_dimension_id_date IS
  'Open date or most recent reopen date';
COMMENT ON COLUMN dwh.facts.days_to_resolution IS
  'Number of days between opening and most recent close';
COMMENT ON COLUMN dwh.facts.days_to_resolution_active IS
  'Number of days open - including only reopens';
COMMENT ON COLUMN dwh.facts.days_to_resolution_from_reopen IS
  'Number of days between last reopening and most recent close';
COMMENT ON COLUMN dwh.facts.hashtag_number IS
  'Number of hashtags in the note (use fact_hashtags bridge table for actual hashtags)';
COMMENT ON COLUMN dwh.facts.action_timezone_id IS
  'Timezone of the action (local)';
COMMENT ON COLUMN dwh.facts.local_action_dimension_id_date IS
  'Local date id for the action';
COMMENT ON COLUMN dwh.facts.local_action_dimension_id_hour_of_week IS
  'Local hour-of-week id for the action';
COMMENT ON COLUMN dwh.facts.action_dimension_id_season IS
  'Season id at the action moment (based on country and date)';
COMMENT ON COLUMN dwh.facts.comment_length IS
  'Length of the comment text';
COMMENT ON COLUMN dwh.facts.has_url IS
  'True if comment contains URL';
COMMENT ON COLUMN dwh.facts.has_mention IS
  'True if comment mentions another user';
COMMENT ON COLUMN dwh.facts.total_comments_on_note IS
  'Total comments count on this note UP TO this action (calculated by trigger)';
COMMENT ON COLUMN dwh.facts.total_reopenings_count IS
  'Total reopenings count on this note UP TO this action (calculated by trigger)';
COMMENT ON COLUMN dwh.facts.total_actions_on_note IS
  'Total actions count on this note UP TO this action (calculated by trigger)';

CREATE TABLE dwh.dimension_users (
 dimension_user_id SERIAL,
 user_id INTEGER NOT NULL,
 username VARCHAR(256),
 modified BOOLEAN,
 valid_from TIMESTAMP,
 valid_to TIMESTAMP,
 is_current BOOLEAN
);
COMMENT ON TABLE dwh.dimension_users IS 'Dimension for users';
COMMENT ON COLUMN dwh.dimension_users.dimension_user_id IS 'Surrogated ID';
COMMENT ON COLUMN dwh.dimension_users.user_id IS 'OSM User ir';
COMMENT ON COLUMN dwh.dimension_users.username IS
  'Username at the moment of the last note';
COMMENT ON COLUMN dwh.dimension_users.modified IS
  'Flag to mark users that have performed note actions';
COMMENT ON COLUMN dwh.dimension_users.valid_from IS 'Validity start (SCD2)';
COMMENT ON COLUMN dwh.dimension_users.valid_to IS 'Validity end (SCD2)';
COMMENT ON COLUMN dwh.dimension_users.is_current IS 'Current row flag (SCD2)';

CREATE TABLE dwh.dimension_continents (
 dimension_continent_id SERIAL,
 continent_name_es VARCHAR(32),
 continent_name_en VARCHAR(32)
);
COMMENT ON TABLE dwh.dimension_continents IS 'Continents';
COMMENT ON COLUMN dwh.dimension_continents.dimension_continent_id IS 'Id';
COMMENT ON COLUMN dwh.dimension_continents.continent_name_es IS
  'Continent name in Spanish';
COMMENT ON COLUMN dwh.dimension_continents.continent_name_en IS
  'Continent name in English';

CREATE TABLE dwh.dimension_regions (
 dimension_region_id SERIAL,
 region_name_es VARCHAR(60),
 region_name_en VARCHAR(60),
 continent_id INTEGER
);
COMMENT ON TABLE dwh.dimension_regions IS 'Regions for contries';
COMMENT ON COLUMN dwh.dimension_regions.dimension_region_id IS 'Id';
COMMENT ON COLUMN dwh.dimension_regions.region_name_es IS
  'Name of the region in Spanish';
COMMENT ON COLUMN dwh.dimension_regions.region_name_en IS
  'Name of the region in English';
COMMENT ON COLUMN dwh.dimension_regions.continent_id IS
  'Continent id';

CREATE TABLE dwh.dimension_countries (
 dimension_country_id SERIAL,
 country_id INTEGER NOT NULL,
 country_name VARCHAR(100),
 country_name_es VARCHAR(100),
 country_name_en VARCHAR(100),
 iso_alpha2 VARCHAR(2),
 iso_alpha3 VARCHAR(3),
 region_id INTEGER,
 modified BOOLEAN
);
COMMENT ON TABLE dwh.dimension_countries IS 'Dimension for contries';
COMMENT ON COLUMN dwh.dimension_countries.dimension_country_id IS
  'Surrogated ID';
COMMENT ON COLUMN dwh.dimension_countries.country_id IS
  'OSM Contry relation ID';
COMMENT ON COLUMN dwh.dimension_countries.country_name IS
  'Name in local language';
COMMENT ON COLUMN dwh.dimension_countries.country_name_es IS 'Name in English';
COMMENT ON COLUMN dwh.dimension_countries.country_name_en IS 'Name in Spanish';
COMMENT ON COLUMN dwh.dimension_countries.iso_alpha2 IS 'ISO 3166-1 alpha-2';
COMMENT ON COLUMN dwh.dimension_countries.iso_alpha3 IS 'ISO 3166-1 alpha-3';
COMMENT ON COLUMN dwh.dimension_countries.modified IS
 'Flag to mark countries that have note actions on them';

CREATE TABLE dwh.dimension_days (
 dimension_day_id SERIAL,
 date_id DATE,
 year SMALLINT,
 month SMALLINT,
 day SMALLINT,
 iso_year SMALLINT,
 iso_week SMALLINT,
 day_of_year SMALLINT,
 quarter SMALLINT,
 month_name VARCHAR(16),
 day_name VARCHAR(16),
 is_weekend BOOLEAN,
 is_month_end BOOLEAN,
 is_quarter_end BOOLEAN,
 is_year_end BOOLEAN
);
COMMENT ON TABLE dwh.dimension_days IS 'Dimension for days';
COMMENT ON COLUMN dwh.dimension_days.dimension_day_id IS 'Surrogated ID';
COMMENT ON COLUMN dwh.dimension_days.date_id IS 'Complete date';
COMMENT ON COLUMN dwh.dimension_days.year IS 'Year of the date';
COMMENT ON COLUMN dwh.dimension_days.month IS 'Month of the date';
COMMENT ON COLUMN dwh.dimension_days.day IS 'Day of date';
COMMENT ON COLUMN dwh.dimension_days.iso_year IS 'ISO year';
COMMENT ON COLUMN dwh.dimension_days.iso_week IS 'ISO week (1..53)';
COMMENT ON COLUMN dwh.dimension_days.day_of_year IS 'Day of year (1..366)';
COMMENT ON COLUMN dwh.dimension_days.quarter IS 'Quarter (1..4)';
COMMENT ON COLUMN dwh.dimension_days.month_name IS 'Month name (en)';
COMMENT ON COLUMN dwh.dimension_days.day_name IS 'Day name (en, ISO)';
COMMENT ON COLUMN dwh.dimension_days.is_weekend IS 'ISO weekend flag';
COMMENT ON COLUMN dwh.dimension_days.is_month_end IS 'Month-end flag';
COMMENT ON COLUMN dwh.dimension_days.is_quarter_end IS 'Quarter-end flag';
COMMENT ON COLUMN dwh.dimension_days.is_year_end IS 'Year-end flag';

CREATE TABLE dwh.dimension_time_of_week (
 dimension_tow_id SMALLINT,
 day_of_week SMALLINT,
 hour_of_day SMALLINT,
 hour_of_week SMALLINT,
 period_of_day VARCHAR(16)
);
COMMENT ON TABLE dwh.dimension_time_of_week IS
  'Dimension for time of the week (ISO: DOW 1..7, HOUR 0..23)';
COMMENT ON COLUMN dwh.dimension_time_of_week.dimension_tow_id IS
  'Id: day_of_week*100 + hour_of_day';
COMMENT ON COLUMN dwh.dimension_time_of_week.day_of_week IS
  'ISO day of the week (1..7)';
COMMENT ON COLUMN dwh.dimension_time_of_week.hour_of_day IS
  'Hour of the day (0..23)';
COMMENT ON COLUMN dwh.dimension_time_of_week.hour_of_week IS
  'Hour of the week (0..167)';
COMMENT ON COLUMN dwh.dimension_time_of_week.period_of_day IS
  'Night/Morning/Afternoon/Evening';

CREATE TABLE dwh.dimension_applications (
 dimension_application_id SERIAL,
 application_name VARCHAR(64) NOT NULL,
 pattern VARCHAR(64),
 pattern_type VARCHAR(16),
 platform VARCHAR(16),
 vendor VARCHAR(32),
 category VARCHAR(32),
 active BOOLEAN
);
COMMENT ON TABLE dwh.dimension_applications IS
  'Dimension for applications creating notes';
COMMENT ON COLUMN dwh.dimension_applications.dimension_application_id IS
  'Surrogated ID';
COMMENT ON COLUMN dwh.dimension_applications.application_name IS
  'Complete name of the application';
COMMENT ON COLUMN dwh.dimension_applications.pattern IS
  'Pattern to find in the comment''text with a SIMILAR TO predicate';
COMMENT ON COLUMN dwh.dimension_applications.pattern_type IS
  'Matching operator: SIMILAR, LIKE or REGEXP';
COMMENT ON COLUMN dwh.dimension_applications.platform IS
  'Platform of the appLication';
COMMENT ON COLUMN dwh.dimension_applications.vendor IS 'Vendor/author';
COMMENT ON COLUMN dwh.dimension_applications.category IS 'Category/type';
COMMENT ON COLUMN dwh.dimension_applications.active IS 'Active flag';

CREATE TABLE dwh.dimension_application_versions (
 dimension_application_version_id SERIAL,
 dimension_application_id INTEGER NOT NULL,
 version VARCHAR(32) NOT NULL
);
COMMENT ON TABLE dwh.dimension_application_versions IS 'Application versions';
COMMENT ON COLUMN dwh.dimension_application_versions.dimension_application_version_id IS 'Id';
COMMENT ON COLUMN dwh.dimension_application_versions.dimension_application_id IS 'FK to application';
COMMENT ON COLUMN dwh.dimension_application_versions.version IS 'Version string';

CREATE TABLE dwh.dimension_hashtags (
 dimension_hashtag_id SERIAL,
 description TEXT
);
COMMENT ON TABLE dwh.dimension_hashtags IS
  'Dimension for hashtags';
COMMENT ON COLUMN dwh.dimension_hashtags.dimension_hashtag_id IS
  'Surrogated ID';
COMMENT ON COLUMN dwh.dimension_hashtags.description IS
  'Description of the hashtag, only for popular ones';

CREATE TABLE dwh.dimension_timezones (
 dimension_timezone_id SERIAL,
 tz_name VARCHAR(64) NOT NULL,
 utc_offset_minutes SMALLINT
);
COMMENT ON TABLE dwh.dimension_timezones IS 'Timezones';
COMMENT ON COLUMN dwh.dimension_timezones.tz_name IS 'IANA tz name (e.g. UTC)';
COMMENT ON COLUMN dwh.dimension_timezones.utc_offset_minutes IS 'UTC offset';

CREATE TABLE dwh.dimension_seasons (
 dimension_season_id SMALLINT,
 season_name_en VARCHAR(16),
 season_name_es VARCHAR(16)
);
COMMENT ON TABLE dwh.dimension_seasons IS 'Seasons for temporal analysis';
COMMENT ON COLUMN dwh.dimension_seasons.dimension_season_id IS 'Id';
COMMENT ON COLUMN dwh.dimension_seasons.season_name_en IS 'Season (en)';
COMMENT ON COLUMN dwh.dimension_seasons.season_name_es IS 'Season (es)';

CREATE TABLE dwh.fact_hashtags (
 fact_id INTEGER NOT NULL,
 dimension_hashtag_id INTEGER NOT NULL,
 position SMALLINT,
 -- Hashtag action classification
 used_in_action note_event_enum,
 is_opening_hashtag BOOLEAN DEFAULT FALSE,
 is_resolution_hashtag BOOLEAN DEFAULT FALSE
);
COMMENT ON TABLE dwh.fact_hashtags IS 'Bridge table facts <-> hashtags';
COMMENT ON COLUMN dwh.fact_hashtags.used_in_action IS 'Action type where hashtag was used (opened/commented/closed/etc)';
COMMENT ON COLUMN dwh.fact_hashtags.is_opening_hashtag IS 'True if hashtag was used in note opening';
COMMENT ON COLUMN dwh.fact_hashtags.is_resolution_hashtag IS 'True if hashtag was used in note resolution/closure';

CREATE TABLE dwh.properties (
 key VARCHAR(16) PRIMARY KEY,
 value VARCHAR(26)
);
COMMENT ON TABLE dwh.properties IS 'Properties table for ETL';
COMMENT ON COLUMN dwh.properties.key IS 'Property name (PRIMARY KEY)';
COMMENT ON COLUMN dwh.properties.value IS 'Property value';

