-- Create partitions for dwh.facts table.
-- This script dynamically creates partitions from 2013 to current year + 1.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2025-10-21

DO /* Notes-ETL-createFactPartitions */ $$
DECLARE
  v_start_year INTEGER := 2013;
  v_current_year INTEGER := EXTRACT(YEAR FROM CURRENT_DATE);
  v_next_year INTEGER := v_current_year + 1;
  v_end_year INTEGER := v_next_year + 1; -- Include current + next + 1
  v_year INTEGER;
  v_partition_name TEXT;
  v_start_date TEXT;
  v_end_date TEXT;
  v_partitions_created INTEGER := 0;
BEGIN
  RAISE NOTICE 'Verifying and creating partitions for dwh.facts';
  RAISE NOTICE 'Current year: %, ensuring partitions exist up to %',
    v_current_year, v_end_year;

  -- Always ensure we have partitions for:
  -- - Historical years (2013 to current-1)
  -- - Current year (most important!)
  -- - Next year (to avoid failures on year transition)
  -- - One more year ahead (buffer)

  v_year := v_start_year;
  WHILE v_year <= v_end_year LOOP
    v_partition_name := 'facts_' || v_year;
    v_start_date := v_year || '-01-01';
    v_end_date := (v_year + 1) || '-01-01';

    -- Check if partition already exists
    IF NOT EXISTS (
      SELECT 1 FROM pg_tables
      WHERE schemaname = 'dwh'
        AND tablename = v_partition_name
    ) THEN
      -- Create partition
      EXECUTE format(
        'CREATE TABLE dwh.%I PARTITION OF dwh.facts
         FOR VALUES FROM (%L) TO (%L)',
        v_partition_name,
        v_start_date,
        v_end_date
      );

      v_partitions_created := v_partitions_created + 1;

      -- Highlight current year partition creation
      IF v_year = v_current_year THEN
        RAISE NOTICE 'Created partition for CURRENT YEAR: % [% to %]',
          v_partition_name, v_start_date, v_end_date;
      ELSIF v_year = v_next_year THEN
        RAISE NOTICE 'Created partition for NEXT YEAR: % [% to %]',
          v_partition_name, v_start_date, v_end_date;
      ELSE
        RAISE NOTICE 'Created partition: % [% to %]',
          v_partition_name, v_start_date, v_end_date;
      END IF;
    ELSE
      -- Only log if it is current or next year (avoid spam)
      IF v_year >= v_current_year THEN
        RAISE NOTICE 'Partition % already exists', v_partition_name;
      END IF;
    END IF;

    v_year := v_year + 1;
  END LOOP;

  -- Create DEFAULT partition for any future dates beyond end_year
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'dwh'
      AND tablename = 'facts_default'
  ) THEN
    CREATE TABLE dwh.facts_default PARTITION OF dwh.facts DEFAULT;
    RAISE NOTICE 'Created DEFAULT partition for future dates';
    v_partitions_created := v_partitions_created + 1;
  END IF;

  -- Summary
  IF v_partitions_created > 0 THEN
    RAISE NOTICE 'Created % new partitions', v_partitions_created;
  ELSE
    RAISE NOTICE '==> All required partitions already exist';
  END IF;

  RAISE NOTICE '==> Partition verification completed successfully';

  -- Verify critical partitions
  IF NOT EXISTS (
    SELECT 1 FROM pg_tables
    WHERE schemaname = 'dwh'
      AND tablename = 'facts_' || v_current_year
  ) THEN
    RAISE EXCEPTION 'CRITICAL: Partition for current year (%) is missing!', v_current_year;
  END IF;

END $$;

-- Verify created partitions
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables
WHERE schemaname = 'dwh'
  AND tablename LIKE 'facts_%'
ORDER BY tablename;

COMMENT ON TABLE dwh.facts IS
  'Facts table (partitioned by action_at year), center of the star schema';

