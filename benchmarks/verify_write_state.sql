-- Compare this output before and after benchmarking; all values must match.
SET search_path TO whatsapp;
SELECT 'messages',count(*) FROM messages
UNION ALL SELECT 'receipts',count(*) FROM message_receipts
UNION ALL SELECT 'memberships',count(*) FROM chat_members;
SELECT message_id,read_at,delivered_at FROM message_receipts
WHERE message_id IN (SELECT message_id FROM messages WHERE chat_id=22556)
AND user_id=965 ORDER BY message_id;
SELECT * FROM messages WHERE message_id IN (90000001,119989) ORDER BY message_id;
SELECT * FROM message_receipts WHERE message_id=1 AND user_id BETWEEN 2 AND 5001 ORDER BY user_id;
SELECT * FROM chat_members WHERE chat_id=20898 AND user_id=965;
