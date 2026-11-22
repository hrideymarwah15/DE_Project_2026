-- CP4: isolated monthly partitioning demonstration. Run with psql -v ON_ERROR_STOP=1.
-- This is a design experiment, not a migration of the production tables.
BEGIN;
CREATE SCHEMA cp4_partition_demo;
CREATE TABLE cp4_partition_demo.messages (
    LIKE whatsapp.messages INCLUDING DEFAULTS INCLUDING CONSTRAINTS,
    PRIMARY KEY (message_id, sent_at)
) PARTITION BY RANGE (sent_at);
CREATE TABLE cp4_partition_demo.messages_june PARTITION OF cp4_partition_demo.messages
    FOR VALUES FROM ('2026-06-01 00:00:00+05:30') TO ('2026-07-01 00:00:00+05:30');
CREATE TABLE cp4_partition_demo.messages_other PARTITION OF cp4_partition_demo.messages DEFAULT;
CREATE INDEX ON cp4_partition_demo.messages (chat_id, sent_at DESC);
INSERT INTO cp4_partition_demo.messages SELECT * FROM whatsapp.messages;
ANALYZE cp4_partition_demo.messages;
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM cp4_partition_demo.messages
WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND sent_at < TIMESTAMPTZ '2026-07-01 00:00:00+05:30';
-- Only the June partition should appear in the plan.
-- PostgreSQL requires the partition key in a partitioned primary/unique key.
-- Receipts and reply references currently use message_id alone. A real migration
-- must redesign those foreign keys or introduce a global message identity table.
-- LIKE does not copy foreign keys; this copy is deliberately not the live schema.
ROLLBACK;
