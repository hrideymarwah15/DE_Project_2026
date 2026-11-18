-- SC-Disruption (T0124) - CP3 optimized queries.
-- Each optimized query is labeled with its workload ID and preserves the
-- original columns, filters, and business meaning while using safer/faster constructs.

BEGIN;
SET search_path TO whatsapp;

-- =====================================================================
-- R13 — Group admins: questions asked in group 20501 that nobody has replied to
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

COMMIT;