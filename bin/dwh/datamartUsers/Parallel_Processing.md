# Parallel Processing with Intelligent Prioritization - DatamartUsers

## Overview

The datamart user processing system implements an **intelligent prioritization** scheme that
processes the most relevant users first, followed by parallel processing to maximize performance.
This ensures that active user data is available quickly, even when there are thousands of modified
users.

## Problem Solved

**Before:** Sequential processing without prioritization resulted in:

- Days of processing without completion
- Active users waiting hours/days for updated data
- Inactive users consuming valuable resources

**Now:** With intelligent prioritization and work queue parallel processing:

- Active users processed in minutes
- Fresh data available quickly for queries
- Inactive users processed in background without affecting active users
- **Optimal CPU utilization:** Fast users don't leave threads idle
- **Dynamic load balancing:** Threads always stay busy
- **Cycle-based processing:** Processes MAX_USERS_PER_CYCLE users per cycle (default: 1000) to allow
  ETL to complete quickly and update data promptly

## Prioritization System

### 6-Level Criteria

The system orders users using multiple cascading criteria:

#### **Level 1: Activity Recency** (Primary Criterion)

```sql
CASE
  WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '7 days' THEN 1   -- CRITICAL
  WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '30 days' THEN 2  -- HIGH
  WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '90 days' THEN 3 -- MEDIUM
  ELSE 4                                                              -- LOW/LOWEST
END
```

- **CRITICAL (1):** Users with activity in last 7 days
- **HIGH (2):** Users with activity in last 30 days
- **MEDIUM (3):** Users with activity in last 90 days
- **LOW/LOWEST (4):** Users without recent activity

#### **Level 2: Historical Activity** (Secondary Criterion)

```sql
CASE
  WHEN COUNT(*) > 100 THEN 1   -- Very active historically
  WHEN COUNT(*) > 10 THEN 2    -- Moderately active
  ELSE 3                        -- Low activity
END
```

- **Very active (>100 actions):** Frequently queried users
- **Moderately active (10-100 actions):** Occasional users
- **Low activity (<10 actions):** Rarely queried users

#### **Level 3: Total Actions** (Tiebreaker)

```sql
COUNT(*) DESC
```

- Orders by total actions (highest to lowest)
- Most active users first within the same level

#### **Level 4: Most Recent Date** (Final Tiebreaker)

```sql
MAX(f.action_at) DESC NULLS LAST
```

- Orders by last action date (most recent first)
- Users without actions at the end

### Complete Prioritization Query

```sql
SELECT DISTINCT
  f.action_dimension_id_user
FROM dwh.facts f
JOIN dwh.dimension_users u
  ON (f.action_dimension_id_user = u.dimension_user_id)
WHERE u.modified = TRUE
GROUP BY f.action_dimension_id_user
ORDER BY
  -- Priority 1: Very recent activity (last 7 days) = highest
  CASE WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '7 days' THEN 1
       WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '30 days' THEN 2
       WHEN MAX(f.action_at) >= CURRENT_DATE - INTERVAL '90 days' THEN 3
       ELSE 4 END,
  -- Priority 2: High activity users (>100 actions) get priority
  CASE WHEN COUNT(*) > 100 THEN 1
       WHEN COUNT(*) > 10 THEN 2
       ELSE 3 END,
  -- Priority 3: Most active users historically
  COUNT(*) DESC,
  -- Priority 4: Most recent activity first
  MAX(f.action_at) DESC NULLS LAST
LIMIT ${MAX_USERS_PER_CYCLE}  -- Process only N users per cycle (default: 1000)
```

## Parallel Processing

### Architecture (Work Queue System)

The system processes users in parallel using a **shared work queue** for dynamic load balancing.
Each worker thread takes the next available user from the queue after finishing one, ensuring
optimal CPU utilization.

```
┌─────────────────────────────────────────┐
│  Prioritized User Query                  │
│  (Ordered by relevance)                  │
└──────────────┬──────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────┐
│  Shared Work Queue File                 │
│  (Thread-safe with flock)               │
└──────────────┬──────────────────────────┘
               │
       ┌───────┴───────┐
       │               │
       ▼               ▼
┌──────────┐    ┌──────────┐
│ Thread 1 │    │ Thread 2 │    ...
│          │    │          │
│ Takes A  │    │ Takes B  │
│ Takes E  │    │ Takes C  │
│ Takes H  │    │ Takes D  │
│ ...      │    │ ...      │
└──────────┘    └──────────┘
```

### Work Queue Implementation

```bash
# Create shared work queue file
work_queue_file="${TMP_DIR}/user_work_queue.txt"
echo "${user_ids}" > "${work_queue_file}"  # Already ordered by priority

# Threads persistentes que toman trabajo de la cola
for ((thread_num=1; thread_num<=adjusted_threads; thread_num++)); do
  (
    while true; do
      # Get next user from queue (thread-safe)
      user_id=$(__get_next_user_from_queue)
      if [[ -z "${user_id}" ]]; then
        break  # Queue empty
      fi
      # Process user...
    done
  ) &
done
```

**Features:**

- Uses `nproc - 1` threads to leave one core free
- **Work queue:** Threads pull work as they become available
- **Dynamic load balancing:** Fast users don't leave threads idle
- **Maintains prioritization:** Queue is created with users already ordered
- **Persistent threads:** Each thread processes multiple users

### Atomic Transactions

Each user is processed in an explicit transaction:

```sql
BEGIN;
  CALL dwh.update_datamart_user(user_id);
  UPDATE dwh.dimension_users
    SET modified = FALSE
    WHERE dimension_user_id = user_id;
COMMIT;
```

**Benefits:**

- **Atomicity:** If `update_datamart_user()` fails, user is not marked as processed
- **Consistency:** The `modified` flag is only updated if processing succeeds
- **Isolation:** Each user is processed independently
- **Durability:** Changes are only committed with successful COMMIT

## Error Handling

### In SQL (Procedure)

```sql
BEGIN
  CALL dwh.update_datamart_user(r.dimension_user_id);
  UPDATE dwh.dimension_users SET modified = FALSE
    WHERE dimension_user_id = r.dimension_user_id;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'Failed to process user %: %', r.dimension_user_id, SQLERRM;
  -- Continue with next user instead of failing entire batch
END;
```

**Features:**

- Captures errors without stopping entire process
- Logs warnings for debugging
- Continues with next user
- User remains `modified = TRUE` for retry

### In Bash (Main Script)

```bash
# Each background process verifies its own success
(
  if ! __psql_with_appname ... -c "BEGIN; ... COMMIT;"; then
    __loge "ERROR: Failed to process user ${user_id}"
    exit 1
  fi
) &

# Wait and count errors
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    failed_count=$((failed_count + 1))
  fi
done
```

**Features:**

- Each process reports its own status
- Errors don't stop other processes
- Failure counter for final report
- Detailed logging per user

## Logging and Monitoring

### Logged Information

1. **Processing Start:**

   ```
   Found X users to process (prioritized by relevance)
   Using Y parallel threads for user processing
   ```

2. **Progress (every 100 users per thread):**

   ```
   Thread 1: Processed 100 users (current: user 12345)
   Thread 2: Processed 200 users (current: user 67890)
   ```

3. **Individual Errors:**

   ```
   Thread 1: ERROR: Failed to process user 12345
   ```

4. **Thread Completion:**

   ```
   Thread 1: Completed successfully (1250 users processed)
   Thread 2: Completed successfully (1248 users processed)
   Thread 3: Completed successfully (1252 users processed)
   ```

5. **Final Summary:**
   ```
   SUCCESS: Datamart users population completed successfully
   Processed 5000 users in parallel (5000 total)
   All users processed with intelligent prioritization (recent → active → inactive)
   ⏱️  TIME: Parallel user processing took 1800 seconds
   ```

### Recommended Metrics

- **Processing time:** Total and per batch
- **Throughput:** Users processed per minute
- **Success rate:** Percentage of successfully processed users
- **Priority distribution:** How many users in each level
- **Average time per user:** By priority level

## Cycle-Based Processing

### Why Limit Users Per Cycle?

The system processes a **limited number of users per ETL cycle** (default: 1000) to ensure:

1. **ETL Completes Quickly:** The ETL process can finish in a reasonable time and free up resources
2. **Prompt Data Updates:** Most active users are processed first, so fresh data is available
   quickly
3. **System Responsiveness:** The system remains responsive for ongoing incremental updates
4. **Progressive Processing:** Less active users are processed in subsequent cycles without blocking
   active users

### How It Works

- **Prioritization:** Users are ordered by activity (most active first)
- **Limit:** Only the top N users (MAX_USERS_PER_CYCLE) are processed per cycle
- **Next Cycle:** Remaining users are processed in the next ETL cycle
- **Result:** Most important users get fresh data quickly, while less active users are processed
  progressively

### Example Scenario

**Initial State:** 50,000 modified users

**Cycle 1 (1000 users):**

- 50 users with activity in last 7 days → **Processed first**
- 200 users with activity in last 30 days → **Processed next**
- 750 users with high historical activity → **Processed next**
- **Result:** ETL completes in ~30 minutes, most active users have fresh data

**Cycle 2 (next ETL run, 1000 users):**

- Next batch of prioritized users
- **Result:** More users get fresh data, ETL still completes quickly

**Cycle 3+:** Continues until all users are processed

**Key Benefit:** Active users have fresh data in minutes, not hours/days.

## Processing Old Users (PROCESS_OLD_USERS)

### ⚠️ NOT RECOMMENDED - Use Only for Initial Load

The `PROCESS_OLD_USERS` option processes **all users** including inactive ones (users with ≤20
actions, which represent ~95% of users). This is **extremely slow** and **not recommended** for
regular ETL cycles.

### Why It's Slow

1. **OFFSET Pagination:** Uses `OFFSET` which requires PostgreSQL to count and skip all previous
   rows. Each batch becomes slower than the previous one.
2. **No Prioritization:** Processes users in order of `user_id`, not by activity or relevance.
3. **Full Table Scans:** Requires `GROUP BY` and `HAVING` on the entire `facts` table for each
   batch.
4. **Estimated Time:** Can take **days or weeks** to complete (e.g., 239 days at current rate).

### When to Use

**Only use `PROCESS_OLD_USERS=yes` for:**

- Initial datamart creation when you need to process ALL users
- One-time historical data backfill

**Never use for:**

- Regular ETL cycles
- Incremental updates
- Production environments with active data

### Recommended Approach

Instead of `PROCESS_OLD_USERS=yes`, use the default behavior (`PROCESS_OLD_USERS=no`):

1. **Process modified users only** - Much faster, only processes users with changes
2. **Intelligent prioritization** - Most active users processed first
3. **Cycle-based processing** - Limits users per cycle (default: 1000) for quick ETL completion
4. **Incremental updates** - Users are marked as `modified=TRUE` when their data changes, so they'll
   be processed in subsequent cycles

### Configuration

```bash
# In etc/properties.sh or environment variable
PROCESS_OLD_USERS=no  # Recommended (default)
# PROCESS_OLD_USERS=yes  # Only for initial load
```

### Performance Comparison

| Approach                         | Users Processed                  | Time             | Use Case           |
| -------------------------------- | -------------------------------- | ---------------- | ------------------ |
| `PROCESS_OLD_USERS=no` (default) | Modified users only (~1000-5000) | Minutes to hours | Regular ETL cycles |
| `PROCESS_OLD_USERS=yes`          | ALL users (~547K)                | Days to weeks    | Initial load only  |

## Configuration

### Environment Variables

```bash
# Maximum number of threads (default: nproc)
MAX_THREADS="${MAX_THREADS:-$(nproc)}"

# Maximum users to process per ETL cycle (default: 1000)
# This limits processing to allow ETL to complete quickly
# Users are prioritized by activity, so most active users are processed first
MAX_USERS_PER_CYCLE="${MAX_USERS_PER_CYCLE:-1000}"

# Batch size for logging (default: 1000)
batch_size=1000
```

### Recommended Adjustments

**For systems with many users:**

- Increase `MAX_THREADS` if resources are available
- Monitor `max_connections` in PostgreSQL
- Adjust `MAX_USERS_PER_CYCLE` based on ETL cycle time requirements
  - **Default (1000):** Good balance for most systems
  - **Higher (2000-5000):** If you have more resources and longer ETL windows
  - **Lower (500):** If you need faster ETL completion times
- Adjust `batch_size` for logging based on volume

**For systems with limited resources:**

- Reduce `MAX_THREADS` to `nproc - 2`
- Reduce `MAX_USERS_PER_CYCLE` to 500 for faster ETL completion
- Increase `batch_size` for less logging
- Processing happens automatically across multiple cycles

## Expected Performance

### Typical Scenarios

**Case 1: 1000 modified users (all processed in one cycle)**

- Active users (7 days): ~50 users → **2-5 minutes**
- Active users (30 days): ~200 users → **10-15 minutes**
- Inactive users: ~750 users → **30-60 minutes**
- **Total:** ~1 hour (vs. days without prioritization)

**Case 2: 10000 modified users (processed across multiple cycles)**

- **Cycle 1 (1000 users):**
  - Active users (7 days): ~50 users → **2-5 minutes**
  - Active users (30 days): ~200 users → **10-15 minutes**
  - High activity users: ~750 users → **30-60 minutes**
  - **Total Cycle 1:** ~1 hour
- **Cycle 2-10:** Remaining users processed progressively
- **Key benefit:** Most active users have fresh data in ~1 hour, not days/weeks

**Case 3: 50000 modified users (large initial load)**

- **Cycle 1 (1000 users):** Most active users → **~1 hour**
- **Cycles 2-50:** Remaining users processed progressively
- **Key benefit:** Active users have fresh data quickly, ETL completes promptly each cycle

## Security Considerations

### Data Integrity

- ✅ **Atomicity:** Transactions guarantee all-or-nothing
- ✅ **Isolation:** Each user is processed independently
- ✅ **Consistency:** `modified` flag only updated after success
- ✅ **Durability:** COMMIT only if everything succeeds

### Resource Contention

- ⚠️ **Locks:** PostgreSQL uses row-level locking
- ⚠️ **Connections:** Limit according to `max_connections`
- ⚠️ **CPU/Memory:** Monitor usage during processing
- ⚠️ **I/O:** Concurrent reads may saturate disk

### Mitigations

1. **Concurrency limit:** `nproc - 1` threads
2. **Work queue:** Dynamic load balancing prevents idle threads
3. **Short transactions:** Each user is independent
4. **Error handling:** Doesn't stop entire process
5. **File locking:** Thread-safe queue access with `flock`

## Troubleshooting

### Problem: Very slow processing

**Possible causes:**

- Too many inactive users being processed first
- Lock contention in database
- System resources saturated

**Solutions:**

- Verify prioritization is working (check logs)
- Reduce `MAX_THREADS`
- Verify indexes on `dwh.facts` and `dwh.dimension_users`
- Monitor locks: `SELECT * FROM pg_locks WHERE NOT granted;`

### Problem: Many errors

**Possible causes:**

- Corrupted data for some user
- Connection timeouts
- Connection limit reached

**Solutions:**

- Review specific error logs
- Verify `max_connections` in PostgreSQL
- Increase timeout if necessary
- Process problematic users manually

### Problem: Users not being processed

**Possible causes:**

- Prioritization query too slow
- Memory limit reached
- Deadlocks

**Solutions:**

- Verify `action_at` has index
- Reduce batch size
- Check deadlocks: `SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';`

## Best Practices

1. **Monitor regularly:**
   - Processing time
   - Success rate
   - Distribution by priority

2. **Adjust based on metrics:**
   - Increase concurrency if resources allow
   - Adjust prioritization criteria based on usage patterns
   - Optimize queries if slow

3. **Preventive maintenance:**
   - Analyze tables regularly (`ANALYZE`)
   - Verify indexes
   - Clean up very old users if necessary

4. **Document changes:**
   - Record configuration adjustments
   - Document problems encountered
   - Share performance metrics

## References

- **Main file:** `bin/dwh/datamartUsers/datamartUsers.sh`
- **Population SQL:** `sql/dwh/datamartUsers/datamartUsers_32_populateDatamartUsersTable.sql`
- **Procedure:** `sql/dwh/datamartUsers/datamartUsers_12_createProcedure.sql`

## Version History

- **v1.0 (2025-12-27):** Initial implementation with static pool
- **v2.0 (2025-01-XX):** Migrated to work queue for dynamic load balancing (DM-006)
- **v2.1 (2026-01-03):** Added cycle-based processing limit (MAX_USERS_PER_CYCLE)
  - Processes maximum 1000 users per cycle (configurable)
  - Allows ETL to complete quickly and update data promptly
  - Most active users processed first, less active users processed progressively
- **Author:** Andres Gomez (AngocA)
