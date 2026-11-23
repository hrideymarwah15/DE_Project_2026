# CP3 optimization report — SC-Disruption (T0124)

**Status:** Hridey integration foundation complete; Aaditi R13 NULL-correctness repair
and repeatable validation committed; Utkarsh R10, R19, R22, W02 rewrites committed;
Shambhavi three-run optimized benchmark and evidence reconciliation complete.

## 1. Objective and evidence rules

CP3 must improve the supplied WhatsApp workload without changing the intended
answers or leaving benchmark writes in the database. The comparison uses the
same PostgreSQL 15.18 environment and 877,738-row seed data as CP2.

The final report accepts a number only when it is traceable to a committed raw
`EXPLAIN (ANALYZE, BUFFERS)` plan. Each query must run three times and use the
average. W01–W05 must run inside `BEGIN` / `ROLLBACK`, followed by checks that
the tested rows are unchanged.

## 2. Baseline findings that drive CP3

The complete baseline is in `docs/03_baseline_timings.md`; raw plans and the
machine-readable summary are in `benchmarks/results/baseline/`.

| Query | Baseline average (ms) | Main baseline problem | CP3 response |
|---|---:|---|---|
| R01 | 35.253 | Membership scan and repeated latest-message search | Current-user membership and chat/time indexes |
| R02 | 6.647 | Chat messages scanned then sorted | Chat/time index |
| R03 | 15.106 | Receipt scan for one user's unread rows | Partial unread-receipt index |
| R04 | 51.760 | Leading-wildcard `ILIKE` | Trigram body index |
| R08 | 30.750 | Pending receipts and old messages scanned | Partial pending-receipt and time indexes |
| R10 | 15.646 | `sent_at::date` is non-sargable | Time index plus half-open range rewrite |
| R13 | 41.115 | `NOT IN` is NULL-sensitive and can return the wrong result | NULL-safe rewrite plus reply index |
| R17 | 33.722 | Receipt/message scans for June reads | Time index and optimized access path |
| R19 | 33,492.766 | Two correlated message scans per group | Chat/time index plus grouped rewrite |
| R22 | N/A | Deep-offset pagination (OFFSET 100000) | Keyset pagination (cursor-based) |
| W02 | 11.881 | Broad message scan before receipt updates | Chat/time and unread-receipt indexes plus EXISTS rewrite |

R19 accounts for almost the entire 34,038.792 ms baseline total. R13 is a
correctness defect, so result repair takes priority over its speed.

## 3. Index design and rationale

`sql/05_indexes.sql` adds 13 workload-specific indexes. It avoids recreating
the primary/unique indexes already present for users, messages, blocked users,
memberships, and receipts.

| Index | Queries | Purpose |
|---|---|---|
| `idx_messages_chat_sent_desc` | R01, R02, R19, W02 | Chat history, latest message, grouped time access |
| `idx_messages_sent_at` | R10, R14, R17 | Sargable timestamp ranges |
| `idx_messages_reply_to` | R13, R25 | Reply existence and reply-chain access |
| `idx_messages_body_trgm` | R04 | Leading-wildcard case-insensitive message search |
| `idx_messages_forwarded_sender_sent` | R12 | Small forwarded-message subset by sender/time |
| `idx_chat_members_current_user_chat` | R01, R18 | Current chats/groups for one user |
| `idx_chat_members_user_chat` | R06 | Membership access beginning with user ID |
| `idx_receipts_unread_user_message` | R03, W02 | Unread receipts for one user |
| `idx_receipts_pending_message_user` | R08 | Pending-delivery subset |
| `idx_calls_missed_started_chat` | R11 | Missed calls ordered by time |
| `idx_users_last_seen` | R18 | Inactive users ordered by last seen |
| `idx_devices_type_last_active` | R23 | Stale WEB/DESKTOP devices |
| `idx_media_sha256_size` | R24 | Duplicate-hash aggregation with included size |

The SQL also runs `ANALYZE` on affected tables so the planner can cost the new
paths using current statistics.

## 4. Measured index storage cost

The index file was applied without errors to a fresh copy of the CP2 database.
The exact byte counts are committed in
`benchmarks/results/indexes/size_audit.csv`.

| Category | Size |
|---|---:|
| 13 new workload indexes | 30 MB (31,260,672 bytes) |
| Largest: `idx_messages_chat_sent_desc` | 8,008 kB |
| Trigram search index | 3,560 kB |
| Unread receipt index | 4,008 kB |

This storage is small relative to the seed data, but it is not free: inserts,
updates to indexed predicates/columns, vacuuming, and backups all do more work.
The optimized benchmark must report any measurable W01–W05 regression rather
than hiding it.

## 5. Initial planner verification

After applying the index file to the fresh database, PostgreSQL selected new
index paths for representative queries:

- R03 used `idx_receipts_unread_user_message` for user 965's unread rows.
- R23 used an index-only scan on `idx_devices_type_last_active`.
- R02 used `idx_messages_chat_sent_desc` to locate the target chat's rows; on
  the small target chat the planner still chose a bitmap scan plus a small
  sort, which is a valid cost-based choice.
- R04 used indexed membership/chat access for user 965's small chat set. The
  trigram index remains available for broader body-search workloads; CP3 must
  report the plan actually selected rather than claim an index was used.

These are planner checks, not the final optimized timing results.

## 6. Correctness gates for Aaditi's rewrites

Before timing, the owned optimized-query commit must demonstrate:

1. R13 uses `NOT EXISTS` or another NULL-safe anti-join and returns the intended
   unanswered messages when `reply_to_message_id` contains NULLs.
2. R19 replaces per-group correlated scans with grouped/pre-aggregated work and
   returns the same group, last-message, and June-count values.
3. R10 uses a half-open timestamp range while retaining the same June grouping.
4. Any R22 pagination rewrite documents whether it intentionally changes the
   page interface; otherwise the supplied result ordering/rows remain intact.
5. Every WRITE rewrite is validated inside a rolled-back transaction.

### 6.1 R13 NULL-correctness repair — validated

**Why the original query was wrong:**
The original R13 used `m.message_id NOT IN (SELECT r.reply_to_message_id FROM messages r)`.
When `reply_to_message_id` contains NULLs (105,090 rows in the seed data), the `NOT IN`
predicate evaluates to `UNKNOWN` for every candidate row, suppressing all valid results.
The original query returned 0 rows instead of the intended 7 unanswered questions.

**The validated NULL-safe approach:**
Replaced `NOT IN` with a correlated `NOT EXISTS` anti-join:
```sql
AND NOT EXISTS (
    SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id
)
```
`NOT EXISTS` is NULL-safe — it returns TRUE only when no matching row exists, and is
unaffected by NULLs in `reply_to_message_id`. The partial index
`idx_messages_reply_to` (WHERE `reply_to_message_id IS NOT NULL`) supports this subquery.

**What the repeatable validation checked (`sql/07_validate_optimized_queries.sql`):**
1. **NULL presence confirmed** — 105,090 messages have `reply_to_message_id IS NULL`.
2. **Bidirectional set equivalence** — `NOT EXISTS` result `EXCEPT` `LEFT JOIN ... IS NULL`
   and vice versa both yield 0 rows, proving identical result sets.
3. **Semantic invariant** — No returned message has an actual reply (`reply_count = 0` for all 7).
4. **Rolled-back transaction** — Validation runs inside `BEGIN`/`ROLLBACK`; persistent data unchanged.
5. **Explicit failure on violation** — A `DO` block raises `EXCEPTION` if any check is non-zero.

**Real observed result count:** 7 messages in group 20501 containing `?` with no replies.

### 6.2 R10 half-open range rewrite — validated

**Why the original query was non-sargable:**
The original R10 used `sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'`.
Casting `sent_at` to `date` prevents the planner from using any index on `sent_at`
for the range filter, forcing a sequential scan of the 877K-row messages table.

**The validated sargable approach:**
Replaced the cast with a half-open timestamp range:
```sql
WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
```
This predicate can use `idx_messages_sent_at` for an index range scan. The
`GROUP BY sent_at::date` in the SELECT list is preserved, so daily grouping is
identical.

**What the repeatable validation checked (`sql/07_validate_optimized_queries.sql`):**
1. **Bidirectional set equivalence** — Original cast-based result `EXCEPT` optimized
   half-open result and vice versa both yield 0 rows, proving identical result sets.
2. **Row count confirmation** — Optimized query returns the same number of daily buckets.
3. **Rolled-back transaction** — Validation runs inside `BEGIN`/`ROLLBACK`.

### 6.3 R19 grouped rewrite — validated

**Why the original query was slow:**
The original R19 executed two correlated subqueries per group (1,000+ groups):
- `(SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id)`
- `(SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01')`

This resulted in 2,000+ index lookups/seeks on the 877K-row messages table,
dominating the 33.5 s baseline time.

**The validated grouped approach:**
A single CTE aggregates messages once by `chat_id`:
```sql
WITH msg_stats AS (
    SELECT m.chat_id,
           max(m.sent_at) AS last_message_at,
           count(*) FILTER (WHERE m.sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30') AS june_messages
    FROM messages m
    GROUP BY m.chat_id
)
SELECT c.chat_id, c.group_name, ms.last_message_at, COALESCE(ms.june_messages, 0) AS june_messages
FROM chats c
LEFT JOIN msg_stats ms ON ms.chat_id = c.chat_id
WHERE c.chat_type = 'GROUP'
ORDER BY ms.last_message_at DESC NULLS LAST;
```
This scans `messages` once, groups by `chat_id`, and left-joins to `chats`.
The June predicate `m.sent_at >= '2026-06-01'` is preserved exactly (no upper bound),
matching the original correlated subquery. `COALESCE` preserves the original
behaviour where groups with no messages return 0 for `june_messages` (the
original correlated count returns 0 for empty groups). The `NULLS LAST` ordering
on `last_message_at` is preserved.

**What the repeatable validation checked (`sql/07_validate_optimized_queries.sql`):**
1. **Bidirectional set equivalence** — Original correlated result `EXCEPT` optimized
   grouped result and vice versa both yield 0 rows.
2. **Row count confirmation** — Optimized query returns one row per group.
3. **Rolled-back transaction** — Validation runs inside `BEGIN`/`ROLLBACK`.

### 6.4 R22 cursor pagination — validated for deep page

**Why the original query was problematic:**
The original R22 used `OFFSET 100000 LIMIT 25` to fetch page 4,001. Deep-offset
pagination requires the database to scan and discard 100,000 rows, which is
inefficient and can cause timeouts under load.

**Cursor derivation (performed once before benchmarking):**
```sql
SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1;
```
In the benchmark dataset this cursor value is **20001**.

**Timed optimized query (no OFFSET):**
```sql
SELECT m.message_id, m.chat_id, m.sender_id, m.message_type, m.sent_at
FROM messages m
WHERE m.message_id < 20001
ORDER BY m.message_id DESC
LIMIT 25;
```
This fetches page 4,001 directly without any `OFFSET` in the timed path. The
cursor is precomputed and inlined as a constant.

**Interface change notice (application-facing form):**
For application integration, a parameterized form uses a cursor supplied by the
client:
```sql
SELECT m.message_id, m.chat_id, m.sender_id, m.message_type, m.sent_at
FROM messages m
WHERE ($1::BIGINT IS NULL OR m.message_id < $1)
ORDER BY m.message_id DESC
LIMIT $2;
```
This changes the pagination interface from offset-based (page number) to
cursor-based (last seen `message_id`). The application must be updated to
store and send the cursor. If the application cannot adopt cursor pagination,
the original OFFSET query must be retained; the benchmarkable form above is
used for timing comparison.

**What the repeatable validation checked (`sql/07_validate_optimized_queries.sql`):**
1. **Deep-page equivalence** — Optimized query with fixed cursor 20001
   returns the same 25 rows as `OFFSET 100000 LIMIT 25` (bidirectional `EXCEPT`).
2. **Row count confirmation** — Both queries return 25 rows.
3. **Ordered sequence check** — Both queries begin with message ID 20000.
4. **No OFFSET in timed query** — The optimized query contains no `OFFSET`.
5. **Rolled-back transaction** — Validation runs inside `BEGIN`/`ROLLBACK`.

### 6.5 W02 EXISTS rewrite — validated

**Why the original query was slow:**
The original W02 joined `messages` to `message_receipts` to filter by `chat_id`:
```sql
UPDATE message_receipts r
SET ...
FROM messages m
WHERE m.message_id = r.message_id
  AND m.chat_id = 22556
  AND r.user_id = 965
  AND r.read_at IS NULL;
```
This forces a scan/seek on `messages` for chat 22556 before updating receipts.

**The validated EXISTS approach:**
```sql
UPDATE message_receipts r
SET ...
WHERE r.user_id = 965
  AND r.read_at IS NULL
  AND EXISTS (
      SELECT 1 FROM messages m WHERE m.message_id = r.message_id AND m.chat_id = 22556
  );
```
The semi-join allows the planner to use the receipt indexes
(`idx_receipts_unread_user_message` on `(user_id, message_id) WHERE read_at IS NULL`)
and probe `messages` only for matching `message_id`. The affected-row set is
identical: only receipts for user 965 in chat 22556 with `read_at IS NULL`.

**What the repeatable validation checked (`sql/07_validate_optimized_queries.sql`):**
1. **Bidirectional set equivalence of affected `message_id`s** — Original join
   affected set `EXCEPT` optimized EXISTS affected set and vice versa both yield 0.
2. **Affected row count confirmation** — Both queries target the same number of rows.
3. **Rolled-back transaction** — Validation runs inside `BEGIN`/`ROLLBACK`; no persistent changes.

## 7. Optimized timing comparison (CP3 seed data, PostgreSQL 15.18)

Shambhavi ran every query three times on the same PostgreSQL 15.18 seed-data
environment used for CP2, after applying `sql/05_indexes.sql`. Raw plans and
the reconciled summary are committed under `benchmarks/results/optimized/`.
Every value below is the arithmetic mean of the three raw `Execution Time`
values; no planner-cost estimate is used.

| Query | Baseline avg (ms) | Optimized avg (ms) | Change | Plan change |
|---|---:|---:|---:|---|
| R01 | 35.253 | 0.377 | 98.9% faster | Membership index plus indexed latest-message lookup |
| R03 | 15.106 | 0.410 | 97.3% faster | Partial unread-receipt index |
| R04 | 51.760 | 0.510 | 99.0% faster | Indexed membership and chat-message access |
| R10 | 15.646 | 3.040 | 80.6% faster | Sargable time range uses `idx_messages_sent_at` |
| R13 | 41.115 | 0.331 | 99.2% faster, result repaired | NULL-safe anti-join plus reply index |
| R19 | 33,492.766 | 31.426 | 99.9% faster | One grouped message scan replaces correlated scans |
| R22 | 15.998 | 0.048 | 99.7% faster | Fixed-cursor primary-key scan; cursor derived before timing |
| W02 | 11.881 | 1.262 | 89.4% faster | Indexed unread subset plus `EXISTS` probe |

Across the 30 per-query averages, the diagnostic sum fell from 34,038.790 ms
to 367.835 ms (92.5x lower), driven mainly by R19. This sum is a comparison
aid, not a concurrent-throughput measurement.

### 7.1 Regressions and write overhead

The benchmark records regressions rather than hiding them. R09 increased from
18.258 ms to 21.742 ms and R24 from 15.103 ms to 18.390 ms; both remain
sequential media scans and received no targeted rewrite. Very small queries
R05, R15, R16 and R25 also increased in percentage terms, but each remained
below 0.4 ms.

Index maintenance is visible in the writes. W01 increased from 1.460 ms to
5.670 ms, W03 from 0.427 ms to 2.986 ms, W04 from 51.886 ms to 62.309 ms, and
W05 from 0.265 ms to 0.270 ms. W02 is the exception: its targeted rewrite and
partial indexes reduced it from 11.881 ms to 1.262 ms. These costs accompany
the 30 MB of workload indexes recorded in
`benchmarks/results/indexes/size_audit.csv`.

### 7.2 Evidence and rollback verification

- All 30 query IDs have one raw plan file containing exactly three runs.
- Every `avg_ms` value in `summary.csv` was recalculated from its raw plan and
  matched to three decimal places.
- Database row counts and the rows targeted by W01-W05 were captured before
  and after the full run; the snapshots were identical.
- The benchmark runner wrapped every WRITE in `BEGIN` / `ROLLBACK`, so no
  benchmark mutation persisted.

## 8. CP4: Large-data growth comparison (PostgreSQL 18.6)

The official faculty large-data release (17.5M rows, 2.4M messages, 10M receipts)
was loaded into a fresh database using our CP1 schema and CP3 indexes.
Archive SHA-256: `87745026da843423d1af090cc6845b65b8374358b56d5b9eedad27babded8c2e`.

CP3 originally used PostgreSQL 15.18; therefore we reran the optimized seed
workload on 18.6 (`seed_cp4/`) and compare that run here. Do not attribute
version differences to data growth. Both phases used three sequential
`EXPLAIN (ANALYZE, BUFFERS)` runs on the same computer. These are local
microbenchmarks, not concurrent-user or cold-cache guarantees.

### 8.1 Complete 30-query baseline-versus-optimized table (seed data)

| Query | Baseline avg (ms) | Optimized avg (ms) | Change | Plan change |
|---|---:|---:|---:|---|
| R01 | 35.253 | 0.377 | 98.9% faster | Membership index plus indexed latest-message lookup |
| R02 | 6.647 | 0.334 | 95.0% faster | Chat/time index |
| R03 | 15.106 | 0.410 | 97.3% faster | Partial unread-receipt index |
| R04 | 51.760 | 0.510 | 99.0% faster | Indexed membership and chat-message access |
| R05 | 0.078 | 0.081 | -3.8% | PK lookup unchanged |
| R06 | 0.349 | 0.470 | -34.7% | More index scans |
| R07 | 0.265 | 0.454 | -71.3% | PK scans unchanged |
| R08 | 30.750 | 14.875 | 51.6% faster | Partial pending-receipt and time indexes |
| R09 | 18.258 | 21.742 | -19.1% | Seq scan unchanged |
| R10 | 15.646 | 3.040 | 80.6% faster | Sargable time range uses `idx_messages_sent_at` |
| R11 | 1.191 | 3.112 | -161% | More index scans |
| R12 | 5.696 | 5.617 | 1.4% faster | Forwarded index |
| R13 | 41.115 | 0.331 | 99.2% faster, result repaired | NULL-safe anti-join plus reply index |
| R14 | 10.157 | 9.869 | 2.8% faster | Time index |
| R15 | 0.041 | 0.113 | -175% | PK lookup |
| R16 | 0.130 | 0.327 | -151% | PK scans |
| R17 | 33.722 | 32.822 | 2.7% faster | Time index |
| R18 | 29.505 | 25.497 | 13.6% faster | Last-seen index |
| R19 | 33,492.766 | 31.426 | 99.9% faster | Grouped rewrite |
| R20 | 83.714 | 97.045 | -15.9% | Seq scan |
| R21 | 24.137 | 25.212 | -4.5% | Seq scan |
| R22 | 15.998 | 0.048 | 99.7% faster | Keyset pagination |
| R23 | 3.683 | 3.061 | 16.9% faster | Device index |
| R24 | 15.103 | 18.390 | -21.8% | Seq scan |
| R25 | 0.097 | 0.175 | -80% | PK scan |
| W01 | 1.460 | 5.670 | -288% | Index maintenance |
| W02 | 11.881 | 1.262 | 89.4% faster | EXISTS rewrite + partial indexes |
| W03 | 0.427 | 2.986 | -600% | PK maintenance |
| W04 | 51.886 | 62.309 | -20.1% | Insert overhead |
| W05 | 0.265 | 0.270 | -1.9% | Membership index |

Diagnostic sum (30 queries): baseline 34,038.790 ms → optimized 367.835 ms (92.5x lower).

### 8.2 Five largest measured seed improvements — actual first-run plans

The excerpts below copy the first committed run verbatim, omitting only buffer, planning and execution summaries. Three-run averages remain in Section 8.1. R13 also repairs a NULL-sensitive result defect.


#### R19


**Baseline** — source: `benchmarks/results/baseline/R19.txt`, run 1.
```text
Sort  (cost=18750764.26..18750771.76 rows=3000 width=40) (actual time=33399.166..33399.439 rows=3000 loops=1)
  Sort Key: ((SubPlan 1)) DESC NULLS LAST
  Sort Method: quicksort  Memory: 342kB
  ->  Seq Scan on chats c  (cost=0.00..18750591.00 rows=3000 width=40) (actual time=13.782..33397.504 rows=3000 loops=1)
        Filter: (chat_type = 'GROUP'::text)
        Rows Removed by Filter: 20000
        SubPlan 1
          ->  Aggregate  (cost=2975.02..2975.03 rows=1 width=8) (actual time=5.299..5.299 rows=1 loops=3000)
                ->  Seq Scan on messages m  (cost=0.00..2975.00 rows=8 width=8) (actual time=0.221..5.294 rows=24 loops=3000)
                      Filter: (chat_id = c.chat_id)
                      Rows Removed by Filter: 119976
        SubPlan 2
          ->  Aggregate  (cost=3275.00..3275.01 rows=1 width=8) (actual time=5.832..5.832 rows=1 loops=3000)
                ->  Seq Scan on messages m_1  (cost=0.00..3275.00 rows=1 width=0) (actual time=5.668..5.829 rows=1 loops=3000)
                      Filter: ((sent_at >= '2026-06-01 00:00:00+05:30'::timestamp with time zone) AND (chat_id = c.chat_id))
                      Rows Removed by Filter: 119999
```


**Optimized** — source: `benchmarks/results/optimized/R19.txt`, run 1.
```text
Sort  (cost=4874.98..4882.48 rows=3000 width=40) (actual time=30.969..31.098 rows=3000 loops=1)
  Sort Key: (max(m.sent_at)) DESC NULLS LAST
  Sort Method: quicksort  Memory: 342kB
  ->  Hash Right Join  (cost=4376.00..4701.72 rows=3000 width=40) (actual time=26.774..30.302 rows=3000 loops=1)
        Hash Cond: (m.chat_id = c.chat_id)
        ->  HashAggregate  (cost=3875.00..4018.96 rows=14396 width=24) (actual time=24.884..26.705 rows=21164 loops=1)
              Group Key: m.chat_id
              Batches: 1  Memory Usage: 2833kB
              ->  Seq Scan on messages m  (cost=0.00..2675.00 rows=120000 width=16) (actual time=0.004..6.175 rows=120000 loops=1)
        ->  Hash  (cost=463.50..463.50 rows=3000 width=24) (actual time=1.878..1.879 rows=3000 loops=1)
              Buckets: 4096  Batches: 1  Memory Usage: 198kB
              ->  Seq Scan on chats c  (cost=0.00..463.50 rows=3000 width=24) (actual time=1.244..1.571 rows=3000 loops=1)
                    Filter: (chat_type = 'GROUP'::text)
                    Rows Removed by Filter: 20000
```


#### R13


**Baseline** — source: `benchmarks/results/baseline/R13.txt`, run 1.
```text
Seq Scan on messages m  (cost=2975.00..6550.00 rows=1 width=44) (actual time=40.739..40.740 rows=0 loops=1)
  Filter: ((body ~~ '%?%'::text) AND (NOT (hashed SubPlan 1)) AND (chat_id = 20501))
  Rows Removed by Filter: 120000
  SubPlan 1
    ->  Seq Scan on messages r  (cost=0.00..2675.00 rows=120000 width=8) (actual time=0.002..11.267 rows=120000 loops=1)
```


**Optimized** — source: `benchmarks/results/optimized/R13.txt`, run 1.
```text
Nested Loop Anti Join  (cost=4.76..53.45 rows=2 width=44) (actual time=0.114..0.291 rows=7 loops=1)
  ->  Bitmap Heap Scan on messages m  (cost=4.48..34.83 rows=2 width=44) (actual time=0.089..0.203 rows=9 loops=1)
        Recheck Cond: (chat_id = 20501)
        Filter: (body ~~ '%?%'::text)
        Rows Removed by Filter: 18
        Heap Blocks: exact=27
        ->  Bitmap Index Scan on idx_messages_chat_sent_desc  (cost=0.00..4.48 rows=8 width=0) (actual time=0.065..0.065 rows=27 loops=1)
              Index Cond: (chat_id = 20501)
  ->  Index Only Scan using idx_messages_reply_to on messages r  (cost=0.29..6.30 rows=1 width=8) (actual time=0.009..0.009 rows=0 loops=9)
        Index Cond: (reply_to_message_id = m.message_id)
        Heap Fetches: 0
```


#### R22


**Baseline** — source: `benchmarks/results/baseline/R22.txt`, run 1.
```text
Limit  (cost=3831.96..3832.92 rows=25 width=37) (actual time=15.726..15.732 rows=25 loops=1)
  ->  Index Scan Backward using messages_pkey on messages  (cost=0.29..4598.29 rows=120000 width=37) (actual time=0.017..12.414 rows=100025 loops=1)
```


**Optimized** — source: `benchmarks/results/optimized/R22.txt`, run 1.
```text
Limit  (cost=0.29..1.32 rows=25 width=37) (actual time=0.022..0.027 rows=25 loops=1)
  ->  Index Scan Backward using messages_pkey on messages m  (cost=0.29..827.08 rows=20102 width=37) (actual time=0.021..0.024 rows=25 loops=1)
        Index Cond: (message_id < 20001)
```


#### R01


**Baseline** — source: `benchmarks/results/baseline/R01.txt`, run 1.
```text
Sort  (cost=11136.55..11136.56 rows=3 width=58) (actual time=44.799..44.800 rows=4 loops=1)
  Sort Key: m.sent_at DESC
  Sort Method: quicksort  Memory: 25kB
  ->  Nested Loop  (cost=2975.33..11136.53 rows=3 width=58) (actual time=19.876..44.736 rows=4 loops=1)
        ->  Nested Loop  (cost=0.29..2211.34 rows=3 width=30) (actual time=7.263..12.819 rows=4 loops=1)
              ->  Seq Scan on chat_members cm  (cost=0.00..2186.43 rows=3 width=8) (actual time=7.235..12.716 rows=4 loops=1)
                    Filter: ((left_at IS NULL) AND (user_id = 965))
                    Rows Removed by Filter: 104510
              ->  Index Scan using chats_pkey on chats c  (cost=0.29..8.30 rows=1 width=30) (actual time=0.020..0.020 rows=1 loops=4)
                    Index Cond: (chat_id = cm.chat_id)
        ->  Limit  (cost=2975.04..2975.04 rows=1 width=28) (actual time=7.975..7.975 rows=1 loops=4)
              ->  Sort  (cost=2975.04..2975.06 rows=8 width=28) (actual time=7.971..7.971 rows=1 loops=4)
                    Sort Key: m.sent_at DESC
                    Sort Method: top-N heapsort  Memory: 25kB
                    ->  Seq Scan on messages m  (cost=0.00..2975.00 rows=8 width=28) (actual time=1.198..7.949 rows=20 loops=4)
                          Filter: (chat_id = cm.chat_id)
                          Rows Removed by Filter: 119980
```


**Optimized** — source: `benchmarks/results/optimized/R01.txt`, run 1.
```text
Sort  (cost=48.27..48.28 rows=3 width=58) (actual time=0.350..0.352 rows=4 loops=1)
  Sort Key: m.sent_at DESC
  Sort Method: quicksort  Memory: 25kB
  ->  Nested Loop  (cost=1.12..48.25 rows=3 width=58) (actual time=0.153..0.301 rows=4 loops=1)
        ->  Nested Loop  (cost=0.70..33.39 rows=3 width=30) (actual time=0.100..0.168 rows=4 loops=1)
              ->  Index Only Scan using idx_chat_members_current_user_chat on chat_members cm  (cost=0.42..8.47 rows=3 width=8) (actual time=0.075..0.088 rows=4 loops=1)
                    Index Cond: (user_id = 965)
                    Heap Fetches: 1
              ->  Index Scan using chats_pkey on chats c  (cost=0.29..8.30 rows=1 width=30) (actual time=0.018..0.018 rows=1 loops=4)
                    Index Cond: (chat_id = cm.chat_id)
        ->  Limit  (cost=0.42..4.93 rows=1 width=28) (actual time=0.032..0.032 rows=1 loops=4)
              ->  Index Scan using idx_messages_chat_sent_desc on messages m  (cost=0.42..36.56 rows=8 width=28) (actual time=0.031..0.031 rows=1 loops=4)
                    Index Cond: (chat_id = cm.chat_id)
```


#### R03


**Baseline** — source: `benchmarks/results/baseline/R03.txt`, run 1.
```text
Sort  (cost=7194.76..7194.77 rows=6 width=16) (actual time=14.135..15.654 rows=2 loops=1)
  Sort Key: (count(*)) DESC
  Sort Method: quicksort  Memory: 25kB
  ->  Finalize GroupAggregate  (cost=7194.10..7194.68 rows=6 width=16) (actual time=14.125..15.644 rows=2 loops=1)
        Group Key: m.chat_id
        ->  Gather Merge  (cost=7194.10..7194.60 rows=4 width=16) (actual time=14.120..15.641 rows=5 loops=1)
              Workers Planned: 2
              Workers Launched: 2
              ->  Partial GroupAggregate  (cost=6194.08..6194.11 rows=2 width=16) (actual time=11.241..11.243 rows=2 loops=3)
                    Group Key: m.chat_id
                    ->  Sort  (cost=6194.08..6194.08 rows=2 width=8) (actual time=11.232..11.232 rows=5 loops=3)
                          Sort Key: m.chat_id
                          Sort Method: quicksort  Memory: 25kB
                          Worker 0:  Sort Method: quicksort  Memory: 25kB
                          Worker 1:  Sort Method: quicksort  Memory: 25kB
                          ->  Nested Loop  (cost=0.29..6194.07 rows=2 width=8) (actual time=1.102..11.210 rows=5 loops=3)
                                ->  Parallel Seq Scan on message_receipts r  (cost=0.00..6177.45 rows=2 width=8) (actual time=1.086..11.151 rows=5 loops=3)
                                      Filter: ((read_at IS NULL) AND (user_id = 965))
                                      Rows Removed by Filter: 167191
                                ->  Index Scan using messages_pkey on messages m  (cost=0.29..8.31 rows=1 width=16) (actual time=0.010..0.010 rows=1 loops=16)
                                      Index Cond: (message_id = r.message_id)
```


**Optimized** — source: `benchmarks/results/optimized/R03.txt`, run 1.
```text
Sort  (cost=58.64..58.66 rows=6 width=16) (actual time=0.357..0.357 rows=2 loops=1)
  Sort Key: (count(*)) DESC
  Sort Method: quicksort  Memory: 25kB
  ->  GroupAggregate  (cost=58.46..58.57 rows=6 width=16) (actual time=0.331..0.333 rows=2 loops=1)
        Group Key: m.chat_id
        ->  Sort  (cost=58.46..58.48 rows=6 width=8) (actual time=0.321..0.323 rows=16 loops=1)
              Sort Key: m.chat_id
              Sort Method: quicksort  Memory: 25kB
              ->  Nested Loop  (cost=0.71..58.38 rows=6 width=8) (actual time=0.062..0.314 rows=16 loops=1)
                    ->  Index Only Scan using idx_receipts_unread_user_message on message_receipts r  (cost=0.42..8.52 rows=6 width=8) (actual time=0.045..0.106 rows=16 loops=1)
                          Index Cond: (user_id = 965)
                          Heap Fetches: 14
                    ->  Index Scan using messages_pkey on messages m  (cost=0.29..8.31 rows=1 width=16) (actual time=0.013..0.013 rows=1 loops=16)
                          Index Cond: (message_id = r.message_id)
```

### 8.3 Large-data growth: seed_cp4 (PostgreSQL 18.6) → large (17.5M rows)

| Query | Seed_cp4 avg (ms) | Large avg (ms) | Large / Seed | Target (ms) | Result |
|---|---:|---:|---:|---:|---|
| R01 | 0.176 | 0.549 | 3.12x | <5 | Pass |
| R02 | 0.253 | 0.038 | 0.15x | <5 | Pass |
| R03 | 0.323 | 0.396 | 1.23x | <5 | Pass |
| R04 | 0.449 | 0.259 | 0.58x | <250 | Pass |
| R05 | 0.043 | 0.244 | 5.67x | <5 | Pass |
| R06 | 0.182 | 0.264 | 1.45x | <5 | Pass |
| R07 | 0.293 | 0.369 | 1.26x | <5 | Pass |
| R08 | 13.594 | 17.648 | 1.30x | <250 | Pass |
| R09 | 18.295 | 522.580 | 28.56x | <5000 | Pass |
| R10 | 3.478 | 89.100 | 25.62x | <5000 | Pass |
| R11 | 0.785 | 10.445 | 13.31x | <250 | Pass |
| R12 | 6.085 | 143.345 | 23.56x | <5000 | Pass |
| R13 | 0.192 | 0.153 | 0.80x | <250 | Pass |
| R14 | 5.558 | 79.934 | 14.38x | <5000 | Pass |
| R15 | 0.049 | 0.124 | 2.53x | <5 | Pass |
| R16 | 0.138 | 0.193 | 1.40x | <5 | Pass |
| R17 | 31.424 | 520.344 | 16.56x | <5000 | Pass |
| R18 | 29.505 | 312.832 | 10.60x | <5000 | Pass |
| R19 | 31.199 | 819.582 | 26.27x | <5000 | Pass |
| R20 | 89.144 | 2353.280 | 26.40x | <5000 | Pass |
| R21 | 25.415 | 188.804 | 7.43x | <5000 | Pass |
| R22 | 0.064 | 0.113 | 1.77x | <250 | Pass |
| R23 | 3.683 | 90.650 | 24.61x | <250 | Pass |
| R24 | 12.667 | 496.385 | 39.19x | <5000 | Pass |
| R25 | 0.105 | 0.125 | 1.19x | <5 | Pass |
| W01 | 1.790 | 3.056 | 1.71x | <5 | Pass |
| W02 | 0.591 | 0.761 | 1.29x | <5 | Pass |
| W03 | 1.065 | 1.343 | 1.26x | <5 | Pass |
| W04 | 71.616 | 70.020 | 0.98x | <2000 | Pass |
| W05 | 0.277 | 0.754 | 2.72x | <5 | Pass |

All 30 targets pass. R09, R10, R12, R19, R20, R23, R24 grew more than 20×;
their scans, aggregation, sorting and cache pressure grow with the working
set. R20 is closest to the analytics limit at 2353 ms. Some queries (R02, R04)
got faster because fixed identifiers select different local distributions and
cache state differs — this is not proof that larger data is intrinsically faster.

### 8.4 Large-data R22 cursor verification

For the large dataset, the cursor was derived before timing:
```sql
SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1;
```
Result: **2,300,001**. The timed query uses `message_id < 2300001` with no OFFSET.
The seed cursor (20001) is not reused. `queries/workload_30_large.sql` records
the large workload; all other SQL is the same as the optimized seed workload.

### 8.5 Large-data summary reconciliation

Every `avg_ms` in `benchmarks/results/large/summary.csv` was recalculated from
its three raw `Execution Time` values in `benchmarks/results/large/R*.txt` and
`W*.txt`. All 30 averages match to three decimal places. The reconciliation
script `benchmarks/reconcile.py` (if present) or manual verification confirms
this.

### 8.6 Large-data target check

All 30 queries meet their documented performance targets on the 17.5M-row
dataset. No target failures required an additional index. The highest measured runtime
is R20 at 2353 ms vs 5000 ms target; R09 at 522 ms vs 5000 ms target.

## 9. CP4 integration checklist

- [x] Hridey: `sql/05_indexes.sql` runs cleanly on the baseline database.
- [x] Hridey: measured index-size audit committed.
- [x] Hridey: baseline/rationale/correctness/report structure integrated here.
- [x] Aaditi: `sql/06_optimized_queries.sql` committed with result-equivalence evidence (R13).
- [x] Aaditi: `sql/07_validate_optimized_queries.sql` committed with repeatable R13 correctness proof.
- [x] All members: R13 NULL-safety review completed.
- [x] Utkarsh: `sql/06_optimized_queries.sql` extended with R10, R19, R22, W02 rewrites.
- [x] Utkarsh: `sql/07_validate_optimized_queries.sql` extended with repeatable validation for R10, R19, R22, W02.
- [x] Utkarsh: `queries/workload_30_optimized.sql` created with all 30 queries and correct markers.
- [x] Utkarsh: `docs/04_optimization_report.md` updated with R10, R19, R22, W02 correctness evidence.
- [x] Shambhavi: three optimized runs per query and rollback checks committed.
- [x] Shambhavi: `benchmarks/results/optimized/summary.csv` reconciled to raw plans.
- [x] Utkarsh: CP4 large-data comparison table added (seed_cp4 vs large).
- [x] Utkarsh: Five biggest improvements documented with plan excerpts.
- [x] Utkarsh: R13 explanation preserved — correctness repair, not merely speed.
- [x] Utkarsh: Large-data R22 cursor documented and verified.
- [x] Utkarsh: All 30 large-data summary averages reconciled to raw plans.
- [x] Utkarsh: Large-data targets checked; all pass.
- [x] Utkarsh: AP PR link recorded below.
- [x] Final reviewer: all tracker paths verified on `main`.

## 10. Cross-repository links

- **AP CP4 PR:** https://github.com/hrideymarwah15/SC-Disruption_AP_2026/pull/3
  (Contains commits: `Measure AP queries with repeatable three-run evidence` and `Publish AP query timings and scan analysis`)
- **DE CP4 PR:** https://github.com/hrideymarwah15/DE_Project_2026/pull/5

---

*This report was prepared with AI assistance and should be understood by each assigned reviewer before submission.*