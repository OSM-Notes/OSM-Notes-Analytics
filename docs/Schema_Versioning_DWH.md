# Data warehouse schema versioning (`dwh`)

This project registers an independent **semantic version** for the **Analytics data warehouse**
schema in PostgreSQL, separate from OSM-Notes-Ingestion’s `core` contract.

## Table

The shared table is `public.schema_version` (same structure as Ingestion’s contract table):

- `component`: primary key, identifier (`'dwh'` for this project’s warehouse contract; Ingestion uses
  `'core'`)
- `version`: `MAJOR.MINOR.PATCH` string
- `updated_at`: last change time for that component’s version value

**Implementation:** the row for `dwh` is created or updated by
[`sql/dwh/ensure_dwh_schema_version.sql`](../sql/dwh/ensure_dwh_schema_version.sql). It is executed
from [`bin/dwh/ETL.sh`](../bin/dwh/ETL.sh) in `__ensureDwhSchemaVersion`, **on every ETL run** in
`main()` after `__checkBaseTables` / `__createBaseTables` and before fact loading (`__initialFactsParallel`
or `__processNotesETL`). So the contract is applied for both first-time DWH creation (after the full
`__createBaseTables` step, which includes
[`ETL_20_createDWHTables.sql`](../sql/dwh/ETL_20_createDWHTables.sql) among other steps) and for
existing databases, without a full rebuild. The
`CREATE TABLE IF NOT EXISTS` matches Ingestion so mixed or Analytics-only databases behave the same
without clobbering the `core` row.

## Current version (initial)

- `dwh`: `1.0.0`

Bumping this value is done by editing the `INSERT` literal in
`sql/dwh/ensure_dwh_schema_version.sql` and updating this document (and the release notes if
applicable).

## SemVer policy (aligned with Ingestion)

- **MAJOR**: Breaking change for consumers that rely on the DWH as a **stable contract** (e.g. drop
  or rename a table/column, change types or semantics in a way that readers must change).
- **MINOR**: Backward-compatible extension (new nullable column, new table, new optional index, new
  enum label where old clients can ignore it).
- **PATCH**: Non-contract changes (query plans, index tuning, comments, bug fixes that do not alter
  the observable schema contract).

The JSON export / viewer versioning (`.json_export_version`, `metadata.schema_version` in
exports) is **separate**; it tracks export shape for the web viewer, not the PostgreSQL `dwh`
contract.

## Consumers (e.g. OSM-Notes-API)

**Contract:** to assert compatibility with the warehouse, query the `dwh` row explicitly:

```sql
SELECT version
FROM public.schema_version
WHERE component = 'dwh';
```

`core` and `dwh` live in the same table when Ingestion and Analytics share a database, but the
**versions are independent**; do not infer DWH contract from `component = 'core'`.

**Shell guard (e.g. OSM-Notes-API startup, optional):**

```bash
# From OSM-Notes-Analytics (or a vendored copy of etc/schema_compatibility.sh)
# shellcheck source=etc/schema_compatibility.sh
source /path/to/OSM-Notes-Analytics/etc/schema_compatibility.sh
export DBNAME_DWH=notes_dwh
export SCHEMA_DWH_CONSUMER=api
if ! __assert_dwh_schema_compatible; then
  exit 1
fi
```

**Expected range (illustration):** see [`etc/schema_compatibility.sh`](../etc/schema_compatibility.sh):

- `__set_dwh_schema_contract_range` — sets `SCHEMA_DWH_COMPONENT`, `EXPECTED_DWH_SCHEMA_MIN`, `EXPECTED_DWH_SCHEMA_MAX`
- `__assert_dwh_schema_compatible` — optional guard for shell tooling: compares the DB row for
  `component = 'dwh'` to that range (same wildcard rules as Ingestion’s `1.x.x` upper bound)

OSM-Notes-Ingestion’s `etc/schema_compatibility.sh` documents **`core` only**; the DWH contract lives
in **this** repository. `lib/osm-common` does not ship a duplicate of this file; depend on
OSM-Notes-Analytics or vendor `etc/schema_compatibility.sh` when implementing API checks.

## Manual verification (psql)

```bash
psql -d notes_dwh -c "SELECT component, version, updated_at FROM public.schema_version ORDER BY component;"
```

After a successful ETL, you should see a row with `component = dwh` and the current version from
`ensure_dwh_schema_version.sql` (e.g. `1.0.0`).

## Related

- Ingestion (base DB contract): [OSM-Notes-Ingestion `docs/Schema_Versioning.md`](https://github.com/OSM-Notes/OSM-Notes-Ingestion/blob/main/docs/Schema_Versioning.md) (if your deployment uses a separate ingestion DB, it has its own `public.schema_version` and `core` row only there).
