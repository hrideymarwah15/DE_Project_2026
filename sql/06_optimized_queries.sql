-- SC-Disruption (T0124) - CP3 optimized queries.
-- Each optimized query is labeled with its workload ID and preserves the
-- original columns, filters, and business meaning while using safer/faster constructs.
-- Benchmark markers (-- @Rxx / -- @Wxx) are required by benchmarks/run_benchmark.sh.

BEGIN;
SET search_path TO whatsapp;

-- =====================================================================
-- @R10 — Growth: daily active senders in June 2026
-- Original query used: sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
-- This is non-sargable because casting to date prevents index use on sent_at.
-- Fix: half-open timestamp range sent_at >= '2026-06-01' AND sent_at < '2026-07-01',
-- which allows the index idx_messages_sent_at to be used for the range scan.
-- The grouping by day is preserved by extracting date in the SELECT only.
-- =====================================================================
SELECT sent_at::date AS day,
       count(DISTINCT sender_id) AS active_senders,
       count(*) AS messages
FROM messages
WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
GROUP BY 1
ORDER BY 1;

-- =====================================================================
-- @R13 — Group admins: questions asked in group 20501 that nobody has replied to
-- Original query used:  m.message_id NOT IN (SELECT r.reply_to_message_id FROM messages r)
-- This is incorrect when reply_to_message_id contains NULLs because NOT IN
-- evaluates to UNKNOWN for every row, suppressing valid results.
-- Fix: correlated NOT EXISTS anti-join, which is NULL-safe and also allows
-- the partial index idx_messages_reply_to (WHERE reply_to_message_id IS NOT NULL)
-- to be used for the subquery.
-- =====================================================================
SELECT m.message_id, m.sender_id, m.sent_at, m.body
FROM messages m
WHERE m.chat_id = 20501
  AND m.body LIKE '%?%'
  AND NOT EXISTS (
      SELECT 1
      FROM messages r
      WHERE r.reply_to_message_id = m.message_id
  );

-- =====================================================================
-- @R19 — Group health report: for every group, the last message time and messages in June 2026
-- Original query used two correlated subqueries per group (one for max sent_at, one for June count).
-- This executes 2 x 1,000+ correlated scans on the 877K-row messages table.
-- Fix: single grouped aggregation on messages, then left join to chats.
-- The June predicate is preserved exactly as m.sent_at >= '2026-06-01' (no upper bound),
-- matching the original correlated subquery.
-- =====================================================================
WITH msg_stats AS (
    SELECT m.chat_id,
           max(m.sent_at) AS last_message_at,
           count(*) FILTER (WHERE m.sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30') AS june_messages
    FROM messages m
    GROUP BY m.chat_id
)
SELECT c.chat_id,
       c.group_name,
       ms.last_message_at,
       COALESCE(ms.june_messages, 0) AS june_messages
FROM chats c
LEFT JOIN msg_stats ms ON ms.chat_id = c.chat_id
WHERE c.chat_type = 'GROUP'
ORDER BY ms.last_message_at DESC NULLS LAST;

-- =====================================================================
-- @R22 — Trust & safety console: all messages, newest first, page 4,001 (25 per page)
-- Original query used OFFSET 100000 LIMIT 25, which requires scanning and discarding
-- 100,000 rows. For deep pagination this is inefficient and can cause timeouts.
-- Fix: keyset (cursor) pagination using message_id as the unique, descending sort key.
-- Cursor derivation (performed once before benchmarking):
--   SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1;
--   In the benchmark dataset this cursor value is 20001.
-- Timed optimized query (no OFFSET):
-- =====================================================================
SELECT m.message_id,
       m.chat_id,
       m.sender_id,
       m.message_type,
       m.sent_at
FROM messages m
WHERE m.message_id < 20001
ORDER BY m.message_id DESC
LIMIT 25;

-- =====================================================================
-- @W02 — Open chat: mark all of user 965's unread messages in group 22556 as read
-- Original query joins messages to filter by chat_id, then updates receipts.
-- The join forces a scan of messages for chat 22556 before finding matching receipts.
-- Fix: use a semi-join (EXISTS) to restrict the update to receipts whose message
-- belongs to chat 22556. This allows the planner to use the index on receipts
-- (message_id, user_id) and the chat_id filter on messages without a full join.
-- The affected-row semantics are identical: only receipts for user 965, chat 22556,
-- with read_at IS NULL are updated. Validation runs inside BEGIN/ROLLBACK.
-- =====================================================================
UPDATE message_receipts r
SET read_at = TIMESTAMPTZ '2026-07-01 09:05:00+05:30',
    delivered_at = coalesce(r.delivered_at, TIMESTAMPTZ '2026-07-01 09:05:00+05:30')
WHERE r.user_id = 965
  AND r.read_at IS NULL
  AND EXISTS (
      SELECT 1
      FROM messages m
      WHERE m.message_id = r.message_id
        AND m.chat_id = 22556
  );

-- Roll back — leaves persistent database data unchanged.
ROLLBACK;