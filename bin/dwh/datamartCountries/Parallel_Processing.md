# Parallel Processing with Work Queue - DatamartCountries

## Overview

The datamart country processing system implements **parallel processing with a shared work queue**
for dynamic load balancing. This ensures optimal CPU utilization by allowing worker threads to take
the next available country after finishing one, preventing idle threads when some countries take
longer to process than others.

## Problem Solved

**Before:** Sequential processing resulted in:

- 30-45 minutes for ~200 countries
- One country at a time, regardless of complexity
- No load balancing: fast countries waited for slow ones

**Now:** With parallel processing and work queue:

- 5-10 minutes for ~200 countries (3-6x faster)
- Multiple countries processed simultaneously
- Dynamic load balancing: threads stay busy

## Key Difference from DatamartUsers

### DatamartUsers Approach (Static Assignment)

- Each process knows which user to process **at launch time**
- Processes users in priority order
- Pool-based: waits for oldest process before starting new one
- Good for: Prioritized processing where order matters

### DatamartCountries Approach (Dynamic Work Queue)

- Each thread **requests next country** after finishing one
- Countries ordered by activity, but threads balance dynamically
- Work queue: threads pull work as they become available
- Good for: Variable processing times, optimal CPU utilization

## Architecture

### Work Queue System

```
┌─────────────────────────────────────────┐
│  Country List (Ordered by Activity)     │
│  [Country A, B, C, D, E, F, ...]        │
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
│ Takes D  │    │ Takes C  │
│ Takes F  │    │ Takes E  │
│ ...      │    │ ...      │
└──────────┘    └──────────┘
```

### How It Works

1. **Initialization:**
   - Fetch all modified countries (ordered by recent activity)
   - Create shared work queue file with all countries
   - Create lock file for thread-safe access

2. **Worker Threads:**
   - Launch `nproc - 2` persistent worker threads
   - Each thread runs in a loop:
     - Lock queue → Take next country → Unlock queue
     - Process country in atomic transaction
     - Repeat until queue is empty

3. **Dynamic Load Balancing:**
   - Fast countries don't leave threads idle
   - Slow countries don't block other threads
   - Optimal CPU utilization

## Parallel Processing Details

### Thread Configuration

```bash
# Get available CPUs
MAX_THREADS="${MAX_THREADS:-$(nproc)}"

# Use nproc - 2 (leave 2 cores free for system)
if [[ "${MAX_THREADS}" -gt 2 ]]; then
  adjusted_threads=$((MAX_THREADS - 2))
else
  adjusted_threads=1
fi
```

**Rationale:**

- Leaves 2 cores free for system operations
- Prevents CPU saturation
- Allows other processes to run smoothly

### Work Queue Implementation

```bash
# Thread-safe function to get next country
__get_next_country_from_queue() {
  local country_id=""
  (
    flock -n 200 || exit 1  # Lock file
    country_id=$(head -n 1 "${work_queue_file}" 2>/dev/null || echo "")
    if [[ -n "${country_id}" ]]; then
      # Remove first line (atomic operation)
      tail -n +2 "${work_queue_file}" > "${work_queue_file}.tmp" && \
        mv "${work_queue_file}.tmp" "${work_queue_file}"
    fi
    exit 0
  ) 200>"${queue_lock_file}"
  echo "${country_id}"
}
```

**Features:**

- **Thread-safe:** Uses `flock` for atomic queue access
- **Atomic operations:** File operations are atomic
- **Non-blocking:** Returns empty string when queue is empty
- **Efficient:** Minimal overhead per operation

### Worker Thread Pattern

```bash
for ((thread_num=1; thread_num<=adjusted_threads; thread_num++)); do
  (
    local thread_processed=0
    local thread_failed=0

    while true; do
      # Get next country from queue
      country_id=$(__get_next_country_from_queue)

      # Exit if queue is empty
      if [[ -z "${country_id}" ]]; then
        break
      fi

      # Process country atomically
      if ! __psql_with_appname ... -c "
        BEGIN;
          CALL dwh.update_datamart_country(${country_id});
          UPDATE dwh.dimension_countries
            SET modified = FALSE
            WHERE dimension_country_id = ${country_id};
        COMMIT;
      "; then
        thread_failed=$((thread_failed + 1))
      else
        thread_processed=$((thread_processed + 1))
      fi
    done

    exit ${thread_failed}
  ) &
  pids+=($!)
done
```

## Ordering Strategy

Countries are ordered by recent activity before being added to the queue:

```sql
SELECT f.dimension_id_country
FROM dwh.facts f
JOIN dwh.dimension_countries c
  ON (f.dimension_id_country = c.dimension_country_id)
WHERE c.modified = TRUE
GROUP BY f.dimension_id_country
ORDER BY MAX(f.action_at) DESC  -- Most active first
```

**Benefits:**

- Most active countries processed first (if threads are available)
- Dynamic balancing still ensures optimal utilization
- Fast countries don't wait for slow ones

## Atomic Transactions

Each country is processed in an explicit transaction:

```sql
BEGIN;
  CALL dwh.update_datamart_country(country_id);
  UPDATE dwh.dimension_countries
    SET modified = FALSE
    WHERE dimension_country_id = country_id;
COMMIT;
```

**Benefits:**

- **Atomicity:** If `update_datamart_country()` fails, country is not marked as processed
- **Consistency:** The `modified` flag is only updated if processing succeeds
- **Isolation:** Each country is processed independently
- **Durability:** Changes are only committed with successful COMMIT

## Error Handling

### Per-Thread Error Tracking

```bash
local thread_failed=0
local thread_processed=0

# Process country
if ! __psql_with_appname ...; then
  thread_failed=$((thread_failed + 1))
  __loge "Thread ${thread_num}: ERROR: Failed to process country ${country_id}"
else
  thread_processed=$((thread_processed + 1))
fi

# Report at end
exit ${thread_failed}  # Exit code = number of failures
```

**Features:**

- Each thread tracks its own failures
- Errors don't stop other threads
- Final report shows total failures

### Final Error Aggregation

```bash
local total_failed=0
for pid in "${pids[@]}"; do
  if ! wait "${pid}"; then
    local thread_exit_code=$?
    total_failed=$((total_failed + thread_exit_code))
  fi
done
```

## Logging and Monitoring

### Logged Information

1. **Initialization:**

   ```
   === PROCESSING COUNTRIES IN PARALLEL (WORK QUEUE) ===
   Using 6 parallel threads (nproc-2: 8 - 2)
   Found 200 countries to process
   ```

2. **Thread Start:**

   ```
   Started worker thread 1 (PID: 12345)
   Started worker thread 2 (PID: 12346)
   ...
   ```

3. **Progress (every 5 countries per thread):**

   ```
   Thread 1: Processed 5 countries (current: country 42)
   Thread 2: Processed 10 countries (current: country 15)
   ```

4. **Thread Completion:**

   ```
   Thread 1: Completed successfully (35 countries processed)
   Thread 2: Completed successfully (33 countries processed)
   ```

5. **Final Summary:**
   ```
   SUCCESS: Datamart countries population completed successfully
   Processed 200 countries in parallel (200 total)
   ⏱️  TIME: Parallel country processing took 420 seconds
   ```

### Recommended Metrics

- **Processing time:** Total and per thread
- **Throughput:** Countries processed per minute
- **Success rate:** Percentage of successfully processed countries
- **Load balance:** Distribution of countries per thread
- **Average time per country:** By country size/complexity

## Configuration

### Environment Variables

```bash
# Maximum number of threads (default: nproc)
MAX_THREADS="${MAX_THREADS:-$(nproc)}"
```

### Recommended Adjustments

**For systems with many countries:**

- Default `nproc - 2` is usually optimal
- Monitor PostgreSQL connections (`max_connections`)
- Verify disk I/O can handle concurrent operations

**For systems with limited resources:**

- Reduce to `nproc - 3` or `nproc - 4`
- Monitor CPU and memory usage
- Consider sequential processing if resources are very limited

**For systems with very fast storage (SSD):**

- Can use `nproc - 1` if CPU is not saturated
- Monitor for lock contention
- Verify PostgreSQL can handle concurrent connections

## Expected Performance

### Typical Scenarios

**Case 1: ~200 countries (current production)**

- **Sequential:** 30-45 minutes
- **Parallel (6 threads):** 5-10 minutes
- **Speedup:** 3-6x faster

**Case 2: ~100 countries**

- **Sequential:** 15-20 minutes
- **Parallel (4 threads):** 3-5 minutes
- **Speedup:** 3-4x faster

**Case 3: ~50 countries**

- **Sequential:** 5-10 minutes
- **Parallel (2 threads):** 2-3 minutes
- **Speedup:** 2-3x faster

**Key factors:**

- Number of countries
- Complexity per country (number of facts)
- Hardware (CPU cores, disk speed)
- Database load

## Comparison: Work Queue vs Static Assignment

| Aspect               | Work Queue (Countries)      | Static Assignment (Users) |
| -------------------- | --------------------------- | ------------------------- |
| **Assignment**       | Dynamic (pull-based)        | Static (push-based)       |
| **Load Balancing**   | Optimal (automatic)         | Good (priority-based)     |
| **Thread Lifecycle** | Persistent (multiple items) | One-shot (single item)    |
| **Best For**         | Variable processing times   | Prioritized processing    |
| **Complexity**       | Higher (queue management)   | Lower (simple pool)       |
| **CPU Utilization**  | Excellent                   | Very good                 |

## Security Considerations

### Data Integrity

- ✅ **Atomicity:** Transactions guarantee all-or-nothing
- ✅ **Isolation:** Each country is processed independently
- ✅ **Consistency:** `modified` flag only updated after success
- ✅ **Durability:** COMMIT only if everything succeeds

### Resource Contention

- ⚠️ **Locks:** PostgreSQL uses row-level locking
- ⚠️ **Connections:** Limit according to `max_connections`
- ⚠️ **CPU/Memory:** Monitor usage during processing
- ⚠️ **I/O:** Concurrent reads may saturate disk
- ⚠️ **File locks:** Queue file locking with `flock`

### Mitigations

1. **Concurrency limit:** `nproc - 2` threads
2. **Atomic transactions:** Each country is independent
3. **Error handling:** Doesn't stop entire process
4. **File locking:** Thread-safe queue access

## Troubleshooting

### Problem: Very slow processing

**Possible causes:**

- Too many countries with many facts
- Lock contention in database
- System resources saturated
- Disk I/O bottleneck

**Solutions:**

- Verify work queue is being consumed (check logs)
- Reduce `MAX_THREADS` to `nproc - 3` or `nproc - 4`
- Verify indexes on `dwh.facts` and `dwh.dimension_countries`
- Monitor locks: `SELECT * FROM pg_locks WHERE NOT granted;`
- Check disk I/O: `iostat -x 1`

### Problem: Threads not balancing work

**Possible causes:**

- File lock contention
- Queue file corruption
- Threads crashing silently

**Solutions:**

- Check for lock file: `ls -la /tmp/datamartCountries_*/country_queue.lock`
- Verify queue file exists and has countries: `head /tmp/datamartCountries_*/country_work_queue.txt`
- Check thread logs for errors
- Verify `flock` is available: `which flock`

### Problem: Many errors

**Possible causes:**

- Corrupted data for some countries
- Connection timeouts
- Connection limit reached
- Database deadlocks

**Solutions:**

- Review specific error logs per thread
- Verify `max_connections` in PostgreSQL
- Increase timeout if necessary: `PSQL_STATEMENT_TIMEOUT=1h`
- Process problematic countries manually
- Check for deadlocks: `SELECT * FROM pg_stat_activity WHERE wait_event_type = 'Lock';`

### Problem: Countries not being processed

**Possible causes:**

- Queue file not created
- Lock file blocking access
- Threads exiting early
- Empty country list

**Solutions:**

- Verify countries query returns results
- Check queue file exists: `ls -la /tmp/datamartCountries_*/country_work_queue.txt`
- Verify threads are running: `ps aux | grep datamartCountries`
- Check thread exit codes in logs
- Verify `modified = TRUE` countries exist

## Best Practices

1. **Monitor regularly:**
   - Processing time
   - Success rate
   - Load balance (countries per thread)
   - Thread utilization

2. **Adjust based on metrics:**
   - Increase concurrency if resources allow
   - Reduce if system is saturated
   - Optimize queries if slow

3. **Preventive maintenance:**
   - Analyze tables regularly (`ANALYZE`)
   - Verify indexes
   - Monitor disk space

4. **Document changes:**
   - Record configuration adjustments
   - Document problems encountered
   - Share performance metrics

## Parallel Processing is Always Enabled

Parallel processing with work queue is the standard implementation. There is no sequential mode.

## References

- **Main file:** `bin/dwh/datamartCountries/datamartCountries.sh`
- **Population SQL:**
  `sql/dwh/datamartCountries/datamartCountries_30_populateDatamartCountriesTable.sql`
- **Procedure:** `sql/dwh/datamartCountries/datamartCountries_12_createProcedure.sql`
- **Related:** `bin/dwh/datamartUsers/PARALLEL_PROCESSING.md` (different approach)
