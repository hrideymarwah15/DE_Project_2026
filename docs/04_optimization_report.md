# CP3 optimization report — SC-Disruption (T0124)

**Status:** Hridey integration foundation complete; optimized query and measured
benchmark sections remain pending their owned Aaditi and Shambhavi commits.

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
| R10 | 15.646 | `sent_at::date` is non-sargable | Time index plus Aaditi's range rewrite |
| R13 | 41.115 | `NOT IN` is NULL-sensitive and can return the wrong result | NULL-safe rewrite plus reply index |
| R17 | 33.722 | Receipt/message scans for June reads | Time index and optimized access path |
| R19 | 33,492.766 | Two correlated message scans per group | Chat/time index plus grouped rewrite |
| W02 | 11.881 | Broad message scan before receipt updates | Chat/time and unread-receipt indexes plus rewrite |

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

## 7. Optimized timing comparison

This section is intentionally pending Shambhavi's three-run optimized
benchmark. It must be filled from committed files under
`benchmarks/results/optimized/`, not estimated from planner costs.

| Query | Baseline avg (ms) | Optimized avg (ms) | Change | Plan change |
|---|---:|---:|---:|---|
| R01 | 35.253 | Pending | Pending | Pending raw plan |
| R03 | 15.106 | Pending | Pending | Pending raw plan |
| R04 | 51.760 | Pending | Pending | Pending raw plan |
| R10 | 15.646 | Pending | Pending | Pending raw plan |
| R13 | 41.115 | Pending | Correctness first | Pending raw plan |
| R19 | 33,492.766 | Pending | Pending | Pending raw plan |
| W02 | 11.881 | Pending | Pending | Pending raw plan |

The final version must also cover all other workload queries through
`benchmarks/results/optimized/summary.csv`, including regressions.

## 8. CP3 integration checklist

- [x] Hridey: `sql/05_indexes.sql` runs cleanly on the baseline database.
- [x] Hridey: measured index-size audit committed.
- [x] Hridey: baseline/rationale/correctness/report structure integrated here.
- [ ] Aaditi: `sql/06_optimized_queries.sql` committed with result-equivalence evidence.
- [ ] All members: R13 NULL-safety review completed.
- [ ] Shambhavi: three optimized runs per query and rollback checks committed.
- [ ] Shambhavi: `benchmarks/results/optimized/summary.csv` reconciled to raw plans.
- [ ] Final reviewer: pending table replaced with measured values and all tracker
  paths verified on `main`.
