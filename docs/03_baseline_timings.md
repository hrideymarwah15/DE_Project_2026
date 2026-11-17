# Baseline timings — SC-Disruption (T0124)

Measured on 17 November 2026 using PostgreSQL 15.18 on the same Apple
MacBook Pro recorded in team.json. The database contained the unmodified
877,738-row seed export and only PK/UNIQUE constraint indexes. Each supplied
query ran three times with EXPLAIN (ANALYZE, BUFFERS). The workload file was
not edited. Every write ran inside BEGIN/ROLLBACK; post-run checks confirmed
that W01–W05 did not change stored data.

| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|---|---:|---:|---:|---:|
| R01 Chats screen | READ | 44.904 | 30.338 | 30.516 | 35.253 |
| R02 Latest 50 group messages | READ | 6.742 | 6.591 | 6.607 | 6.647 |
| R03 Unread badges | READ | 15.715 | 14.351 | 15.253 | 15.106 |
| R04 Search “meeting” | READ | 56.135 | 49.244 | 49.901 | 51.760 |
| R05 Phone lookup | READ | 0.049 | 0.042 | 0.039 | 0.043 |
| R06 Direct-chat contacts | READ | 5.585 | 6.249 | 6.077 | 5.970 |
| R07 Current group members | READ | 0.582 | 0.576 | 0.561 | 0.573 |
| R08 Pending receipts | READ | 37.294 | 28.074 | 26.882 | 30.750 |
| R09 Top media uploaders | READ | 18.113 | 18.624 | 18.038 | 18.258 |
| R10 June daily active senders | READ | 15.203 | 15.460 | 16.276 | 15.646 |
| R11 Missed calls | READ | 10.055 | 9.902 | 9.727 | 9.895 |
| R12 Repeated forwarding | READ | 12.339 | 12.634 | 12.445 | 12.473 |
| R13 Unanswered questions | READ | 40.800 | 42.218 | 40.326 | 41.115 |
| R14 Most active groups | READ | 13.002 | 12.545 | 12.792 | 12.780 |
| R15 Block check | READ | 0.046 | 0.041 | 0.040 | 0.042 |
| R16 Message read info | READ | 0.175 | 0.146 | 0.196 | 0.172 |
| R17 Average read time | READ | 38.947 | 30.615 | 31.605 | 33.722 |
| R18 Inactive group members | READ | 28.301 | 27.401 | 27.688 | 27.797 |
| R19 Group health | READ | 33,399.912 | 33,923.971 | 33,154.415 | 33,492.766 |
| R20 Messages per hour/type | READ | 94.467 | 97.435 | 102.038 | 97.980 |
| R21 Edit/delete shares | READ | 25.458 | 25.571 | 25.787 | 25.605 |
| R22 Trust console page 4,001 | READ | 15.751 | 15.999 | 16.245 | 15.998 |
| R23 Stale linked devices | READ | 7.383 | 7.282 | 7.245 | 7.303 |
| R24 Duplicate media hashes | READ | 14.912 | 15.347 | 15.051 | 15.103 |
| R25 Reply chain | READ | 0.114 | 0.106 | 0.122 | 0.114 |
| W01 Insert message | WRITE | 1.147 | 1.577 | 1.655 | 1.460 |
| W02 Mark chat read | WRITE | 15.221 | 11.104 | 9.319 | 11.881 |
| W03 Delete for everyone | WRITE | 0.450 | 0.373 | 0.458 | 0.427 |
| W04 Insert broadcast receipts | WRITE | 60.701 | 47.821 | 47.137 | 51.886 |
| W05 Leave group | WRITE | 0.328 | 0.237 | 0.231 | 0.265 |
| **Total** |  | **33,979.831** | **34,451.874** | **33,684.672** | **34,038.792** |

The total is dominated by R19. It is shown for completeness rather than as a
single user-facing latency.

## Plan reading

| Query | Scan type and baseline explanation |
|---|---|
| R01 | Sequential scans of chat_members and messages. The lateral latest-message lookup repeatedly searches messages because chat_id/sent_at has no tuning index. |
| R02 | Sequential scan of all messages, then sort/top-N for one chat. No chat-history index exists. |
| R03 | Sequential receipt scan plus messages PK lookups. user_id/read_at lacks an index. |
| R04 | Sequential scans of messages and membership. Leading-wildcard ILIKE cannot use a B-tree. |
| R05 | users_phone_e164_key index lookup; the natural unique key makes it very fast. |
| R06 | Sequential membership scan, followed by PK/index-only lookups. Filtering by member user_id is not supported by the composite PK's leading column. |
| R07 | chat_members PK range scan and users PK lookup; chat_id is the leading key and the group is small. |
| R08 | Sequential scans of receipts and messages because pending delivery and send-time filters lack suitable indexes. |
| R09 | Sequential media scan and aggregation. Every media row contributes to the report. |
| R10 | Sequential messages scan. Casting sent_at to date makes the predicate non-sargable for a normal timestamp index. |
| R11 | Sequential calls and membership scans; status/time/user access paths are absent. |
| R12 | Sequential messages scan and aggregate; the report examines the forwarded subset without a partial index. |
| R13 | Sequential messages scans. The NOT IN subquery contains NULL reply values, so SQL three-valued logic can make the answer empty; CP3 must correct and prove it. |
| R14 | Sequential messages scan plus chats scan/lookup; the June range has no supporting timestamp index. |
| R15 | blocked_users composite PK index-only lookup exactly matches both key columns. |
| R16 | message_receipts composite PK range scan plus users PK lookup; message_id is the leading key. |
| R17 | Sequential receipt and message scans to aggregate June reads; no time/access-path support exists. |
| R18 | Sequential users and membership scans plus chats lookups; last_seen and current-group membership are unindexed. |
| R19 | For every group, two correlated subqueries repeatedly sequential-scan messages. This is the dominant 33.5-second baseline. |
| R20 | Sequential scan and full aggregation of messages. The report legitimately reads all rows. |
| R21 | Sequential scan and full aggregation of messages. The report also needs every row. |
| R22 | Backward messages PK scan but OFFSET discards 100,000 rows before returning 25. |
| R23 | Sequential device scan; device type and last_active_at are unindexed. |
| R24 | Sequential media scan and hash aggregation; duplicate detection reads all hashes. |
| R25 | Recursive messages PK lookups; each reply hop uses the primary key and is fast. |
| W01 | Direct insert with constraint/PK work; no read scan appears in the plan. |
| W02 | Sequential messages scan followed by receipt PK lookups; chat/user/unread predicates need support. |
| W03 | messages PK lookup updates exactly one row. |
| W04 | generate_series inserts up to 5,000 rows and checks the composite receipt PK; no table scan is needed. |
| W05 | chat_members composite PK lookup updates one membership row. |

Raw plans for all three runs are in benchmarks/results/baseline/R01.txt through
W05.txt. The machine-readable averages and scan nodes are in
benchmarks/results/baseline/summary.csv.
