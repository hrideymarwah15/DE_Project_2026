-- SC-Disruption T0124 — repeatable CP1 validation.
-- Run after sql/01_schema.sql and sql/02_load_data.sql.
-- Every expected/actual pair must match and every violation count must be 0.

\set ON_ERROR_STOP on
SET search_path TO whatsapp;
SET TIME ZONE 'Asia/Kolkata';

SELECT *
FROM (
    VALUES
        ('users', 30000::bigint,
         (SELECT count(*) FROM users)),
        ('devices', 42000::bigint,
         (SELECT count(*) FROM devices)),
        ('chats', 23000::bigint,
         (SELECT count(*) FROM chats)),
        ('chat_members', 104514::bigint,
         (SELECT count(*) FROM chat_members)),
        ('media', 27634::bigint,
         (SELECT count(*) FROM media)),
        ('messages', 120000::bigint,
         (SELECT count(*) FROM messages)),
        ('message_receipts', 501590::bigint,
         (SELECT count(*) FROM message_receipts)),
        ('calls', 25000::bigint,
         (SELECT count(*) FROM calls)),
        ('blocked_users', 4000::bigint,
         (SELECT count(*) FROM blocked_users))
) AS counts(table_name, expected_rows, actual_rows)
ORDER BY table_name;

SELECT 'sender_without_membership' AS check_name, count(*) AS violations
FROM messages m
WHERE NOT EXISTS (
    SELECT 1
    FROM chat_members cm
    WHERE cm.chat_id = m.chat_id
      AND cm.user_id = m.sender_id
)
UNION ALL
SELECT 'reply_in_different_chat', count(*)
FROM messages child
JOIN messages parent ON parent.message_id = child.reply_to_message_id
WHERE child.chat_id <> parent.chat_id
UNION ALL
SELECT 'direct_chat_member_count_not_two', count(*)
FROM (
    SELECT c.chat_id
    FROM chats c
    LEFT JOIN chat_members cm ON cm.chat_id = c.chat_id
    WHERE c.chat_type = 'DIRECT'
    GROUP BY c.chat_id
    HAVING count(cm.user_id) <> 2
) AS invalid_direct_chats
UNION ALL
SELECT 'receipt_read_before_message_sent', count(*)
FROM message_receipts r
JOIN messages m USING (message_id)
WHERE r.read_at < m.sent_at
UNION ALL
SELECT 'media_message_type_mismatch', count(*)
FROM messages m
JOIN media md USING (media_id)
WHERE m.message_type <> md.media_type
ORDER BY check_name;

SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'whatsapp'
ORDER BY tablename, indexname;
