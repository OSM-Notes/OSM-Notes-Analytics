# DWH Queries

This directory contains reusable SQL queries and analysis scripts for the Data Warehouse.

## Available Queries

### DOC-001: User Contribution Statistics

**File**: `DOC_001_user_contribution_stats.sql`

**Purpose**: Analyze user contribution patterns, showing how many users have made only one
contribution and the distribution of users by contribution level.

**Features**:

- Count users with only one contribution
- Distribution of users by contribution level (1, 2-5, 6-10, 11-50, 51-100, 101-500, 501-1000,
  1000+)
- Percentage breakdowns for each category
- Summary statistics (total users, averages, medians, min/max)

**Usage**:

1. **Basic query** - Count single-contribution users:

```sql
SELECT COUNT(1) AS users_with_single_contribution
FROM (
  SELECT f.action_dimension_id_user
  FROM dwh.facts f
  GROUP BY f.action_dimension_id_user
  HAVING COUNT(1) = 1
) AS t;
```

2. **Using the view** - Get distribution:

```sql
SELECT * FROM dwh.v_user_contribution_distribution;
```

3. **Using the function** - Get summary statistics:

```sql
SELECT * FROM dwh.get_user_contribution_summary();
```

**Installation**:

Run the SQL file to create the view and function:

```bash
psql -d notes_dwh -f sql/dwh/queries/DOC_001_user_contribution_stats.sql
```

**Output Example**:

The view provides output like:

```
contribution_level    | user_count | percentage_of_users | total_contributions | percentage_of_contributions
----------------------+------------+---------------------+--------------------+---------------------------
1 contribution        | 15000     | 45.23               | 15000              | 0.15
2-5 contributions     | 8000      | 24.12               | 25000              | 0.25
6-10 contributions    | 3000      | 9.05                | 24000              | 0.24
...
```

The function provides summary statistics:

```
total_users | users_with_single_contribution | percentage_single_contribution | ...
------------+--------------------------------+-------------------------------+-----
33150       | 15000                         | 45.23                         | ...
```

## Adding New Queries

When adding new queries to this directory:

1. Use descriptive filenames with prefixes (e.g., `DOC_002_`, `ANALYSIS_001_`, etc.)
2. Include comprehensive comments explaining the purpose
3. Provide usage examples in comments
4. Consider creating views or functions for reusable queries
5. Update this README with documentation

## Related Documentation

- Original query source: `ToDo/ToDos.md` lines 86-94
- TODO reference: `ToDo/TODO_LIST.md` - DOC-001
