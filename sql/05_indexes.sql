-- SC-Disruption (T0124) - CP3 workload indexes.
-- Apply after sql/01_schema.sql and sql/02_load_data.sql.
-- Each index maps to one or more supplied workload query IDs.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pg_trgm;
SET search_path TO whatsapp, public;

-- R01, R02, R19: latest/history lookup within a chat and group aggregates.
CREATE INDEX IF NOT EXISTS idx_messages_chat_sent_desc
    ON messages (chat_id, sent_at DESC)
    INCLUDE (message_id, sender_id, message_type, reply_to_message_id);

-- R10, R14, R17: range access on message timestamps.
-- R10 must also be rewritten to avoid casting sent_at in its predicate.
CREATE INDEX IF NOT EXISTS idx_messages_sent_at
    ON messages (sent_at);

-- R13, R25: reply existence and reply-chain traversal.
CREATE INDEX IF NOT EXISTS idx_messages_reply_to
    ON messages (reply_to_message_id)
    WHERE reply_to_message_id IS NOT NULL;

-- R04: leading-wildcard, case-insensitive body search.
CREATE INDEX IF NOT EXISTS idx_messages_body_trgm
    ON messages USING gin (body gin_trgm_ops);

-- R12: the forwarded-message subset grouped by sender and day.
CREATE INDEX IF NOT EXISTS idx_messages_forwarded_sender_sent
    ON messages (sender_id, sent_at)
    WHERE is_forwarded;

-- R01, R18: current memberships located from a user.
CREATE INDEX IF NOT EXISTS idx_chat_members_current_user_chat
    ON chat_members (user_id, chat_id)
    WHERE left_at IS NULL;

-- R06: all membership lookups starting from a user, including left chats.
CREATE INDEX IF NOT EXISTS idx_chat_members_user_chat
    ON chat_members (user_id, chat_id);

-- R03, W02: unread receipts for one user.
CREATE INDEX IF NOT EXISTS idx_receipts_unread_user_message
    ON message_receipts (user_id, message_id)
    WHERE read_at IS NULL;

-- R08: the small pending-delivery subset joined back to messages.
CREATE INDEX IF NOT EXISTS idx_receipts_pending_message_user
    ON message_receipts (message_id, user_id)
    WHERE delivered_at IS NULL;

-- R11: missed calls in reverse chronological order.
CREATE INDEX IF NOT EXISTS idx_calls_missed_started_chat
    ON calls (started_at DESC, chat_id)
    INCLUDE (call_id, caller_id, call_type)
    WHERE status = 'MISSED';

-- R18: inactive users ordered by last-seen time.
CREATE INDEX IF NOT EXISTS idx_users_last_seen
    ON users (last_seen_at, user_id)
    INCLUDE (display_name)
    WHERE last_seen_at IS NOT NULL;

-- R23: linked computer devices that have gone stale.
CREATE INDEX IF NOT EXISTS idx_devices_type_last_active
    ON devices (device_type, last_active_at)
    INCLUDE (device_id, user_id)
    WHERE device_type IN ('WEB', 'DESKTOP');

-- R24: duplicate media hashes; size is included for index-only aggregation.
CREATE INDEX IF NOT EXISTS idx_media_sha256_size
    ON media (sha256)
    INCLUDE (size_bytes);

COMMIT;

ANALYZE whatsapp.messages;
ANALYZE whatsapp.chat_members;
ANALYZE whatsapp.message_receipts;
ANALYZE whatsapp.calls;
ANALYZE whatsapp.users;
ANALYZE whatsapp.devices;
ANALYZE whatsapp.media;
