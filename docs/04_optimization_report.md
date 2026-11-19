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

Optimized timing fields remain pending Shambhavi's three-run benchmark evidence.

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

## 7. Optimized timing comparison

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

## 8. CP3 integration checklist

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
- [x] Final reviewer: pending table replaced with measured values and all tracker
  paths verified on the benchmark branch.
