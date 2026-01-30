-- Creates data warehouse relations.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-08-08

-- Primary keys
SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating primary keys' AS Task;

ALTER TABLE dwh.dimension_users
 ADD CONSTRAINT pk_users_dim
 PRIMARY KEY (dimension_user_id);

ALTER TABLE dwh.dimension_regions
 ADD CONSTRAINT pk_regions_dim
 PRIMARY KEY (dimension_region_id);

ALTER TABLE dwh.dimension_countries
 ADD CONSTRAINT pk_countries_dim
 PRIMARY KEY (dimension_country_id);

ALTER TABLE dwh.dimension_days
 ADD CONSTRAINT pk_days_dim
 PRIMARY KEY (dimension_day_id);

ALTER TABLE dwh.dimension_time_of_week
 ADD CONSTRAINT pk_tow_dim
 PRIMARY KEY (dimension_tow_id);

ALTER TABLE dwh.dimension_applications
 ADD CONSTRAINT pk_applications_dim
 PRIMARY KEY (dimension_application_id);

ALTER TABLE dwh.dimension_application_versions
 ADD CONSTRAINT pk_application_versions_dim
 PRIMARY KEY (dimension_application_version_id);

ALTER TABLE dwh.dimension_continents
 ADD CONSTRAINT pk_continents_dim
 PRIMARY KEY (dimension_continent_id);

ALTER TABLE dwh.dimension_timezones
 ADD CONSTRAINT pk_timezones_dim
 PRIMARY KEY (dimension_timezone_id);

ALTER TABLE dwh.dimension_seasons
 ADD CONSTRAINT pk_seasons_dim
 PRIMARY KEY (dimension_season_id);

-- Foreign keys.
SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating foreign keys' AS Task;

ALTER TABLE dwh.dimension_countries
 ADD CONSTRAINT fk_region
 FOREIGN KEY (region_id)
 REFERENCES dwh.dimension_regions (dimension_region_id);

ALTER TABLE dwh.dimension_regions
 ADD CONSTRAINT fk_continent
 FOREIGN KEY (continent_id)
 REFERENCES dwh.dimension_continents (dimension_continent_id);

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating indexes' AS Task;

-- Unique keys

-- For SCD2: ensure uniqueness only on current rows
CREATE UNIQUE INDEX IF NOT EXISTS dimension_user_id_current_uniq
 ON dwh.dimension_users (user_id)
 WHERE is_current;
COMMENT ON INDEX dwh.dimension_user_id_current_uniq IS 'OSM User id (current)';

CREATE UNIQUE INDEX IF NOT EXISTS dimension_username_current_uniq
 ON dwh.dimension_users (username)
 WHERE is_current;
COMMENT ON INDEX dwh.dimension_username_current_uniq IS 'Unique username (current)';

CREATE UNIQUE INDEX dimension_country_id_uniq
 ON dwh.dimension_countries
 (country_id);
COMMENT ON INDEX dwh.dimension_country_id_uniq IS 'OSM Country relation id';

CREATE UNIQUE INDEX dimension_day_id_uniq
 ON dwh.dimension_days
 (date_id);
COMMENT ON INDEX dwh.dimension_day_id_uniq IS 'Date';

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Creating functions' AS Task;
-- Returns or creates an application version row and returns its id
CREATE OR REPLACE FUNCTION dwh.get_application_version_id(
  m_application_id INTEGER,
  m_version TEXT
) RETURNS INTEGER AS
$$
DECLARE
  m_id INTEGER;
BEGIN
  IF m_application_id IS NULL OR m_version IS NULL THEN
    RETURN NULL;
  END IF;
  SELECT dimension_application_version_id INTO m_id
  FROM dwh.dimension_application_versions
  WHERE dimension_application_id = m_application_id AND version = m_version;
  IF m_id IS NULL THEN
    INSERT INTO dwh.dimension_application_versions(
      dimension_application_id, version)
    VALUES (m_application_id, m_version)
    RETURNING dimension_application_version_id INTO m_id;
  END IF;
  RETURN m_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION dwh.get_application_version_id IS 'Gets/creates application version id';


/**
 * Gets the id of the given timestamp. If the ID does not exist, it creates it.
 * If this function is not called at all for a day, they that day will not have
 * an ID, and it will be missing.
 */
CREATE OR REPLACE FUNCTION dwh.get_date_id(new_date TIMESTAMP)
  RETURNS INTEGER AS
 $$
 DECLARE
  m_id_date INTEGER;
 BEGIN
  SELECT /* Notes-ETL */ dimension_day_id
   INTO m_id_date
  FROM dwh.dimension_days
  WHERE date_id = DATE(new_date);

  IF (m_id_date IS NULL) THEN
   INSERT INTO dwh.dimension_days (
     date_id, year, month, day,
     iso_year, iso_week, day_of_year, quarter,
     month_name, day_name,
     is_weekend, is_month_end, is_quarter_end, is_year_end
    ) VALUES (
     DATE(new_date), EXTRACT(YEAR FROM new_date), EXTRACT(MONTH FROM new_date),
     EXTRACT(DAY FROM new_date),
     EXTRACT(ISOYEAR FROM new_date), EXTRACT(WEEK FROM new_date),
     EXTRACT(DOY FROM new_date), EXTRACT(QUARTER FROM new_date),
     TO_CHAR(new_date, 'Mon'), TO_CHAR(new_date, 'Dy'),
     (EXTRACT(ISODOW FROM new_date) IN (6,7)),
     (DATE_TRUNC('month', new_date) + INTERVAL '1 month - 1 day')::DATE = DATE(new_date),
     (EXTRACT(MONTH FROM new_date) IN (3,6,9,12) AND DATE(new_date) = (DATE_TRUNC('quarter', new_date) + INTERVAL '3 month - 1 day')::DATE),
     (DATE_TRUNC('year', new_date) + INTERVAL '1 year - 1 day')::DATE = DATE(new_date)
    )
    ON CONFLICT DO NOTHING -- This should not happen, but happens.
    RETURNING dimension_day_id
     INTO m_id_date
   ;
  END IF;
  RETURN m_id_date;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION dwh.get_date_id IS
  'Returns id of the day';

/**
 * Returns the given hour of a timestamp.
 */
CREATE OR REPLACE FUNCTION dwh.get_hour_of_week_id(m_date TIMESTAMP)
  RETURNS INTEGER AS
 $$
 DECLARE
  m_day_of_week SMALLINT;
  m_hour_of_day SMALLINT;
  m_dimension_tow_id SMALLINT;
  m_hour_of_week SMALLINT;
  m_period_of_day VARCHAR(16);
 BEGIN
  SELECT /* Notes-ETL */ EXTRACT(ISODOW FROM m_date)
   INTO m_day_of_week;

  SELECT /* Notes-ETL */ EXTRACT(HOUR FROM m_date)
   INTO m_hour_of_day;

  m_hour_of_week := (m_day_of_week - 1) * 24 + m_hour_of_day;
  IF (m_hour_of_day BETWEEN 0 AND 5) THEN
    m_period_of_day := 'Night';
  ELSIF (m_hour_of_day BETWEEN 6 AND 11) THEN
    m_period_of_day := 'Morning';
  ELSIF (m_hour_of_day BETWEEN 12 AND 17) THEN
    m_period_of_day := 'Afternoon';
  ELSE
    m_period_of_day := 'Evening';
  END IF;

  SELECT /* Notes-ETL */ dimension_tow_id
   INTO m_dimension_tow_id
  FROM dwh.dimension_time_of_week
  WHERE dimension_tow_id = m_day_of_week * 100 + m_hour_of_day;

  IF (m_dimension_tow_id IS NULL) THEN
   INSERT INTO dwh.dimension_time_of_week (
     dimension_tow_id, day_of_week, hour_of_day, hour_of_week, period_of_day
    ) VALUES (
     m_day_of_week * 100 + m_hour_of_day, m_day_of_week, m_hour_of_day,
     m_hour_of_week, m_period_of_day
    )
   ;
   SELECT /* Notes-ETL */ dimension_tow_id
    INTO m_dimension_tow_id
   FROM dwh.dimension_time_of_week
   WHERE dimension_tow_id = m_day_of_week * 100 + m_hour_of_day;
  END IF;
  RETURN m_dimension_tow_id;
 END;
 $$ LANGUAGE plpgsql
;
COMMENT ON FUNCTION dwh.get_hour_of_week_id IS
  'Returns id of the hour of a week (ISO DOW 1..7, HOUR 0..23)';

-- Gets timezone id by lon/lat using coarse UTC offset bands
CREATE OR REPLACE FUNCTION dwh.get_timezone_id_by_lonlat(
  m_lon DECIMAL,
  m_lat DECIMAL
) RETURNS INTEGER AS
$$
DECLARE
  m_offset SMALLINT;
  m_name VARCHAR(64);
  m_id INTEGER;
BEGIN
  -- If coordinates missing, fallback to UTC
  IF m_lon IS NULL OR m_lat IS NULL THEN
    SELECT dimension_timezone_id INTO m_id
    FROM dwh.dimension_timezones WHERE tz_name = 'UTC' LIMIT 1;
    RETURN m_id;
  END IF;
  -- Round to nearest 15-degree UTC band
  m_offset := ROUND(m_lon / 15.0);
  IF m_offset < -12 THEN m_offset := -12; END IF;
  IF m_offset > 14 THEN m_offset := 14; END IF;
  IF m_offset = 0 THEN
    m_name := 'UTC';
  ELSIF m_offset > 0 THEN
    m_name := 'UTC+' || m_offset::text;
  ELSE
    m_name := 'UTC' || m_offset::text; -- e.g. UTC-5
  END IF;
  SELECT dimension_timezone_id INTO m_id
  FROM dwh.dimension_timezones WHERE tz_name = m_name;
  IF m_id IS NULL THEN
    INSERT INTO dwh.dimension_timezones (tz_name, utc_offset_minutes)
    VALUES (m_name, m_offset * 60)
    RETURNING dimension_timezone_id INTO m_id;
  END IF;
  RETURN m_id;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION dwh.get_timezone_id_by_lonlat IS 'Returns tz id using lon/lat via UTC bands';

-- Local date id using timezone offset
CREATE OR REPLACE FUNCTION dwh.get_local_date_id(
  m_ts TIMESTAMP,
  m_timezone_id INTEGER
) RETURNS INTEGER AS
$$
DECLARE
  m_offset SMALLINT;
  m_local TIMESTAMP;
BEGIN
  SELECT utc_offset_minutes INTO m_offset
  FROM dwh.dimension_timezones WHERE dimension_timezone_id = m_timezone_id;
  IF m_offset IS NULL THEN
    RETURN dwh.get_date_id(m_ts);
  END IF;
  m_local := m_ts + make_interval(mins => m_offset);
  RETURN dwh.get_date_id(m_local);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION dwh.get_local_date_id IS 'Returns local date id using tz';

-- Local hour_of_week id using timezone offset
CREATE OR REPLACE FUNCTION dwh.get_local_hour_of_week_id(
  m_ts TIMESTAMP,
  m_timezone_id INTEGER
) RETURNS INTEGER AS
$$
DECLARE
  m_offset SMALLINT;
  m_local TIMESTAMP;
BEGIN
  SELECT utc_offset_minutes INTO m_offset
  FROM dwh.dimension_timezones WHERE dimension_timezone_id = m_timezone_id;
  IF m_offset IS NULL THEN
    RETURN dwh.get_hour_of_week_id(m_ts);
  END IF;
  m_local := m_ts + make_interval(mins => m_offset);
  RETURN dwh.get_hour_of_week_id(m_local);
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION dwh.get_local_hour_of_week_id IS 'Returns local time-of-week id using tz';

-- Season by timestamp and latitude
CREATE OR REPLACE FUNCTION dwh.get_season_id(
  m_ts TIMESTAMP,
  m_lat DECIMAL
) RETURNS SMALLINT AS
$$
DECLARE
  m_month SMALLINT;
  m_season SMALLINT;
BEGIN
  IF m_lat IS NULL THEN RETURN 0; END IF; -- No season
  m_month := EXTRACT(MONTH FROM m_ts);
  -- Equatorial band: neutral
  IF m_lat BETWEEN -10 AND 10 THEN RETURN 0; END IF;
  -- Northern hemisphere
  IF m_lat > 10 THEN
    IF m_month BETWEEN 3 AND 5 THEN m_season := 1; -- Spring
    ELSIF m_month BETWEEN 6 AND 8 THEN m_season := 2; -- Summer
    ELSIF m_month BETWEEN 9 AND 11 THEN m_season := 3; -- Autumn
    ELSE m_season := 4; -- Winter
    END IF;
  ELSE -- Southern hemisphere
    IF m_month BETWEEN 3 AND 5 THEN m_season := 4; -- Winter (opposite)
    ELSIF m_month BETWEEN 6 AND 8 THEN m_season := 3; -- Autumn
    ELSIF m_month BETWEEN 9 AND 11 THEN m_season := 2; -- Summer
    ELSE m_season := 1; -- Spring
    END IF;
  END IF;
  RETURN m_season;
END;
$$ LANGUAGE plpgsql;
COMMENT ON FUNCTION dwh.get_season_id IS 'Returns season id based on date and latitude';

SELECT /* Notes-ETL */ clock_timestamp() AS Processing,
 'Extra objects created' AS Task;

