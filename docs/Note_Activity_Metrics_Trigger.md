---
title: "Note Activity Metrics Trigger Documentation"
description:
  "This trigger calculates accumulated historical metrics for each note action BEFORE inserting a
  new row into `dwh.facts`. It populates three columns:"
version: "1.0.0"
last_updated: "2026-01-25"
author: "AngocA"
tags:
  - "performance"
audience:
  - "developers"
project: "OSM-Notes-Analytics"
status: "active"
---

# Note Activity Metrics Trigger Documentation

**File:** `sql/dwh/ETL_52_createNoteActivityMetrics.sql`

## Overview

This trigger calculates accumulated historical metrics for each note action BEFORE inserting a new
row into `dwh.facts`. It populates three columns:

- `total_comments_on_note`: Number of comments on this note UP TO this action
- `total_reopenings_count`: Number of reopenings on this note UP TO this action
- `total_actions_on_note`: Total actions on this note UP TO this action

## What Happens When Trigger Is Enabled (Active)

For EVERY INSERT into `dwh.facts`:

1. Trigger executes BEFORE the row is inserted
2. Performs a SELECT COUNT(\*) query to scan previous rows of the same note
3. Calculates accumulated metrics up to (but not including) the current action
4. Sets the three metric columns on the NEW row
5. Row is inserted with metrics already calculated

**Example:** If inserting the 5th action on note #123:

- `total_comments_on_note` = count of 'commented' actions in previous 4 rows
- `total_reopenings_count` = count of 'reopened' actions in previous 4 rows
- `total_actions_on_note` = 4 (previous actions, not including current)

## What Happens When Trigger Is Disabled (Inactive)

For EVERY INSERT into `dwh.facts`:

1. Trigger does NOT execute
2. No SELECT COUNT(\*) query is performed
3. The three metric columns are set to NULL
4. Row is inserted without metrics

### Important Consequences

- Metrics will be NULL for all rows inserted while trigger is disabled
- These NULL values are permanent (not recalculated later)
- Queries filtering/grouping by these metrics will exclude NULL rows
- Analytics requiring these metrics will have incomplete data

## Performance Impact

### When Enabled

- Adds 1 SELECT COUNT(\*) query per INSERT
- Query scans previous rows: `WHERE id_note = NEW.id_note AND fact_id < NEW.fact_id`
- Uses index `resolution_idx (id_note, fact_id)` for optimization
- **Estimated impact:** 5-15% slower ETL during bulk loads
- **Estimated overhead:** ~10-50ms per row inserted (depends on note history)

### When Disabled

- No performance overhead
- ETL runs 5-15% faster during bulk loads
- **Trade-off:** Metrics are NULL (data quality impact)

## Automatic Enable/Disable Behavior

The ETL automatically manages trigger state:

### Initial Load (`__initialFactsParallel`)

1. Trigger is DISABLED before bulk data load (for performance)
2. Data is loaded without metrics (columns are NULL)
3. Trigger is CREATED after load completes
4. Trigger is ENABLED after creation (for future incremental loads)

### Incremental Load (`__processNotesETL`)

1. Trigger is CREATED if it doesn't exist
2. Trigger is ENABLED (metrics are needed for incremental data)
3. New rows are inserted WITH metrics calculated

## Manual Control and Diagnostics

### Check Trigger Status

```sql
SELECT * FROM dwh.get_note_activity_metrics_trigger_status();
```

**Returns:**

- `trigger_name`: Name of the trigger
- `enabled`: TRUE if trigger is active, FALSE if disabled
- `event_manipulation`: 'INSERT' (what event triggers it)
- `action_timing`: 'BEFORE' (when it executes relative to INSERT)

**Use Cases for Status Check:**

1. **Troubleshooting:** Why are metrics NULL in my queries?
   - Check if trigger was accidentally disabled

2. **Post-ETL verification:** Confirm trigger is enabled after load
   - Ensure incremental loads will calculate metrics correctly

3. **Performance investigation:** Verify trigger state before benchmarking
   - Know if performance tests include trigger overhead

4. **Audit/Monitoring:** Track trigger state over time
   - Detect unexpected state changes

5. **Pre-operation check:** Verify state before manual bulk operations
   - Avoid disabling an already-disabled trigger

### Disable Trigger (for manual bulk operations)

```sql
SELECT dwh.disable_note_activity_metrics_trigger();
```

### Enable Trigger (after manual bulk operations)

```sql
SELECT dwh.enable_note_activity_metrics_trigger();
```

## Use Cases and Analytical Value

These metrics enable **HISTORICAL SNAPSHOT ANALYSIS** - understanding what the state of a note was
at ANY specific point in time, not just the current state.

### 1. Engagement Evolution Analysis

**Question:** "How did engagement grow over the note's lifecycle?"

- Track `total_comments_on_note` over time for a specific note
- Identify when notes gain traction, peak engagement moments

### 2. Comment Threshold Analysis

**Question:** "What percentage of notes get closed after X comments?"

- Find notes where `total_comments_on_note = N` at closure time
- Understand if there's a "sweet spot" comment count for resolution

### 3. Reopening Pattern Analysis

**Question:** "Do notes with more reopenings take longer to resolve?"

- Correlate `total_reopenings_count` with `days_to_resolution`
- Identify problematic notes that cycle through reopen/close

### 4. Engagement-to-Resolution Correlation

**Question:** "Is there a relationship between comment count and resolution time?"

- Analyze `total_comments_on_note` vs `days_to_resolution` at closure
- Understand if more discussion helps or hinders resolution

### 5. Historical Context at Moment of Action

**Question:** "What was the engagement level when user X commented?"

- Filter actions by user and see `total_actions_on_note` at that moment
- Understand if users comment more on active vs inactive notes

### 6. Activity Threshold Segmentation

**Question:** "Segment notes by activity level: low/medium/high engagement"

- GROUP BY ranges of `total_actions_on_note` at closure
- Compare resolution patterns across engagement levels

### 7. Reopening Frequency Analysis

**Question:** "Which notes get reopened multiple times and why?"

- Find notes with `total_reopenings_count > 3` at closure
- Identify recurring issues or problematic note patterns

### 8. Longitudinal Engagement Trends

**Question:** "How has average engagement changed over years?"

- Average `total_comments_on_note` by year at closure time
- Track community engagement trends over time

### 9. Early vs Late Engagement

**Question:** "Do notes that get early comments resolve faster?"

- Compare notes with comments in first action vs later
- Understand if early community attention helps resolution

### 10. Action Sequence Analysis

**Question:** "What's the typical sequence of actions for resolved notes?"

- Analyze `total_actions_on_note` progression by action type
- Identify successful resolution patterns

### Current Usage in Codebase

- **datamartGlobal:** Calculates `avg_comments_per_note` (average across all notes)

### Potential Future Usages

- Dashboard visualizations showing engagement over time
- Alert system for notes with unusual activity patterns
- Machine learning features for resolution prediction
- Community behavior analysis reports

## Example Queries

### Example 1: Engagement Evolution for a Specific Note

Show how comments accumulated over time for note #12345:

```sql
SELECT
  action_at,
  action_comment,
  total_comments_on_note,
  total_actions_on_note
FROM dwh.facts
WHERE id_note = 12345
ORDER BY fact_id;
```

### Example 2: Notes Closed After High Engagement

Find notes that were closed after accumulating 10+ comments:

```sql
SELECT
  id_note,
  MAX(total_comments_on_note) as max_comments,
  MAX(total_actions_on_note) as max_actions,
  MAX(days_to_resolution) as resolution_days
FROM dwh.facts
WHERE action_comment = 'closed'
  AND total_comments_on_note >= 10
GROUP BY id_note;
```

### Example 3: Correlation Between Comments and Resolution Time

Do notes with more comments take longer to resolve?

```sql
SELECT
  CASE
    WHEN total_comments_on_note < 3 THEN 'Low (0-2)'
    WHEN total_comments_on_note < 10 THEN 'Medium (3-9)'
    ELSE 'High (10+)'
  END as engagement_level,
  COUNT(*) as notes_count,
  AVG(days_to_resolution) as avg_resolution_days,
  AVG(total_reopenings_count) as avg_reopenings
FROM dwh.facts
WHERE action_comment = 'closed'
  AND total_comments_on_note IS NOT NULL
GROUP BY engagement_level
ORDER BY engagement_level;
```

### Example 4: Reopening Patterns

Find notes that were reopened 3+ times before final closure:

```sql
SELECT
  id_note,
  MAX(total_reopenings_count) as total_reopenings,
  MAX(total_comments_on_note) as total_comments,
  MAX(days_to_resolution) as resolution_days
FROM dwh.facts
WHERE action_comment = 'closed'
  AND total_reopenings_count >= 3
GROUP BY id_note
ORDER BY total_reopenings DESC;
```

### Example 5: Early Engagement Analysis

Compare resolution times for notes with early vs late engagement:

```sql
SELECT
  CASE
    WHEN total_comments_on_note = 0 AND total_actions_on_note = 1 THEN 'No early comments'
    WHEN total_comments_on_note > 0 AND total_actions_on_note <= 3 THEN 'Early comments'
    ELSE 'Late comments'
  END as engagement_timing,
  COUNT(*) as notes,
  AVG(days_to_resolution) as avg_resolution_days
FROM dwh.facts
WHERE action_comment = 'closed'
  AND total_actions_on_note IS NOT NULL
GROUP BY engagement_timing;
```

### Example 6: Activity Level Distribution

Segment notes by activity level at closure:

```sql
SELECT
  CASE
    WHEN total_actions_on_note <= 3 THEN 'Low activity (1-3 actions)'
    WHEN total_actions_on_note <= 10 THEN 'Medium activity (4-10 actions)'
    WHEN total_actions_on_note <= 25 THEN 'High activity (11-25 actions)'
    ELSE 'Very high activity (25+ actions)'
  END as activity_segment,
  COUNT(*) as notes_closed,
  AVG(days_to_resolution) as avg_days,
  AVG(total_comments_on_note) as avg_comments
FROM dwh.facts
WHERE action_comment = 'closed'
  AND total_actions_on_note IS NOT NULL
GROUP BY activity_segment
ORDER BY
  CASE activity_segment
    WHEN 'Low activity (1-3 actions)' THEN 1
    WHEN 'Medium activity (4-10 actions)' THEN 2
    WHEN 'High activity (11-25 actions)' THEN 3
    ELSE 4
  END;
```

### Example 7: Engagement Trend Over Years

How has average engagement changed over time?

```sql
SELECT
  EXTRACT(YEAR FROM dd.date_id) as year,
  COUNT(*) as notes_closed,
  AVG(total_comments_on_note) as avg_comments,
  AVG(total_actions_on_note) as avg_actions
FROM dwh.facts f
JOIN dwh.dimension_days dd ON f.action_dimension_id_date = dd.dimension_day_id
WHERE f.action_comment = 'closed'
  AND f.total_comments_on_note IS NOT NULL
GROUP BY EXTRACT(YEAR FROM dd.date_id)
ORDER BY year;
```

## Technical Notes

- **Trigger type:** BEFORE INSERT (calculates before row is inserted)
- **Does NOT update existing rows** (only sets values on NEW row)
- Each row stores the accumulated state UP TO that specific moment
- Compatible with table partitioning (works on all partitions)
- Index `resolution_idx (id_note, fact_id)` MUST exist before creating trigger

## Related Documentation

- See `tests/performance/benchmark_trigger_performance.sql` for performance testing
- See `ToDo/Progress_Tracker.md` for current development tasks
