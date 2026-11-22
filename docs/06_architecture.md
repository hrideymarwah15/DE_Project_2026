# Scaling beyond the large-data test

Monthly RANGE partitions on `messages.sent_at` help time-bounded analytics and
retention. `sql/08_partitioning.sql` is a reversible demonstration; the committed
plan shows June pruning. Chat history queries without a time range can still
visit multiple partitions, so retain `(chat_id, sent_at DESC)` indexes locally.

The current primary key is `message_id`. A partitioned unique key must include
`sent_at`; switching to `(message_id, sent_at)` requires receipt and reply foreign
keys to carry that timestamp, or a separate global identity table. Do not deploy
the demonstration as a drop-in schema migration. Add future monthly partitions
ahead of time and archive old partitions after checking retention requirements.

At 100 times seed volume, the projection is 12 million messages and about
50 million receipts. This is a capacity estimate, not a measured dataset.
Measure disk, replication lag and backup duration before committing hardware.

Shard by chat when one primary stops meeting write or storage requirements.
R02 remains local to one chat shard. R01 requires gathering a user's memberships
and latest-chat summaries across shards; keep a per-user chat-list projection.
Global analytics need asynchronous aggregation rather than synchronous fan-out.
Sharding by sender makes a chat's history span many shards and complicates reads.

Send historical analytics (R09, R10, R12, R14, R17-R21, R24) to a read replica
when stale results are acceptable. Keep writes, receipt state and immediate
read-after-write checks on the primary. Cache chat metadata and contact lookups
with short expiry and explicit invalidation; do not cache unread counts without
an update strategy. Keyset pagination must use a cursor from the actual dataset.

Monitor dead tuples and autovacuum on messages and receipts. Tune vacuum per
table from observed churn, not a copied global setting. Refresh daily summary
tables for broad reports and keep raw events for reconciliation. Test restore
time and partition retention operations before treating this design as ready.
