-- Run this file from the repository root:
-- psql -X -v ON_ERROR_STOP=1 -d DATABASE -f sql/02_load_data.sql

\set ON_ERROR_STOP on

BEGIN;
SET LOCAL search_path TO whatsapp;
SET LOCAL TIME ZONE 'Asia/Kolkata';

-- Parents are loaded before tables that reference them.
\copy users FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true)
\copy devices FROM 'seed_data/devices.csv' WITH (FORMAT csv, HEADER true)
\copy chats FROM 'seed_data/chats.csv' WITH (FORMAT csv, HEADER true)
\copy chat_members FROM 'seed_data/chat_members.csv' WITH (FORMAT csv, HEADER true)
\copy media FROM 'seed_data/media.csv' WITH (FORMAT csv, HEADER true)
\copy messages FROM 'seed_data/messages.csv' WITH (FORMAT csv, HEADER true)
\copy message_receipts FROM 'seed_data/message_receipts.csv' WITH (FORMAT csv, HEADER true)
\copy calls FROM 'seed_data/calls.csv' WITH (FORMAT csv, HEADER true)
\copy blocked_users FROM 'seed_data/blocked_users.csv' WITH (FORMAT csv, HEADER true)

ANALYZE;
COMMIT;

-- Required row-count verification.
SELECT 'users' AS table_name, count(*) AS rows FROM whatsapp.users
UNION ALL SELECT 'devices', count(*) FROM whatsapp.devices
UNION ALL SELECT 'chats', count(*) FROM whatsapp.chats
UNION ALL SELECT 'chat_members', count(*) FROM whatsapp.chat_members
UNION ALL SELECT 'media', count(*) FROM whatsapp.media
UNION ALL SELECT 'messages', count(*) FROM whatsapp.messages
UNION ALL SELECT 'message_receipts', count(*) FROM whatsapp.message_receipts
UNION ALL SELECT 'calls', count(*) FROM whatsapp.calls
UNION ALL SELECT 'blocked_users', count(*) FROM whatsapp.blocked_users
ORDER BY table_name;
