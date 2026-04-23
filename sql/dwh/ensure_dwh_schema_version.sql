-- Idempotent: ensure public.schema_version exists (same contract as OSM-Notes-Ingestion) and
-- register or refresh the data warehouse (dwh) schema SemVer. Does not modify other components
-- (e.g. core).
--
-- Executed from bin/dwh/ETL.sh on every ETL run so existing databases receive the dwh row without
-- requiring a full DWH rebuild. On version bumps, update the literal in the INSERT and
-- docs/Schema_Versioning_DWH.md.
--
-- Author: Andres Gomez (AngocA)
-- Version: 2026-04-22

CREATE TABLE IF NOT EXISTS public.schema_version (
  component VARCHAR(64) PRIMARY KEY,
  version VARCHAR(16) NOT NULL,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE public.schema_version IS
  'Schema version contract for DB consumers';

COMMENT ON COLUMN public.schema_version.component IS
  'Schema component identifier';

COMMENT ON COLUMN public.schema_version.version IS
  'Schema semantic version (MAJOR.MINOR.PATCH)';

COMMENT ON COLUMN public.schema_version.updated_at IS
  'Timestamp when schema version was updated';

-- DWH contract: independent SemVer from Ingestion public.schema_version (component = 'core').
INSERT INTO public.schema_version (component, version)
VALUES ('dwh', '1.0.0')
ON CONFLICT (component) DO UPDATE
  SET
    version = EXCLUDED.version,
    updated_at = CASE
      WHEN public.schema_version.version IS DISTINCT FROM EXCLUDED.version
        THEN CURRENT_TIMESTAMP
      ELSE public.schema_version.updated_at
    END;
