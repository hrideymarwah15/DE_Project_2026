-- SC-Disruption (T0124) — WhatsApp baseline schema.
-- CP1 permits constraints only. No performance-tuning indexes are created here.

BEGIN;

CREATE SCHEMA whatsapp;
SET search_path TO whatsapp;

CREATE TABLE users (
    user_id       BIGINT PRIMARY KEY CHECK (user_id > 0),
    phone_e164    TEXT NOT NULL UNIQUE
                  CHECK (phone_e164 ~ '^\+[1-9][0-9]{1,14}$'),
    display_name  TEXT NOT NULL CHECK (length(btrim(display_name)) > 0),
    about         TEXT,
    is_business   BOOLEAN NOT NULL DEFAULT FALSE,
    joined_on     DATE NOT NULL,
    last_seen_at  TIMESTAMPTZ,
    status        TEXT NOT NULL
                  CHECK (status IN ('ACTIVE', 'BANNED', 'DELETED'))
);

CREATE TABLE devices (
    device_id       BIGINT PRIMARY KEY CHECK (device_id > 0),
    user_id         BIGINT NOT NULL
                    REFERENCES users(user_id) ON DELETE CASCADE,
    device_type     TEXT NOT NULL
                    CHECK (device_type IN ('ANDROID', 'IOS', 'WEB', 'DESKTOP')),
    app_version     TEXT NOT NULL
                    CHECK (app_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
    registered_at   TIMESTAMPTZ NOT NULL,
    last_active_at  TIMESTAMPTZ NOT NULL,
    CHECK (last_active_at >= registered_at)
);

CREATE TABLE chats (
    chat_id      BIGINT PRIMARY KEY CHECK (chat_id > 0),
    chat_type    TEXT NOT NULL CHECK (chat_type IN ('DIRECT', 'GROUP')),
    group_name   TEXT,
    created_by   BIGINT NOT NULL
                 REFERENCES users(user_id) ON DELETE RESTRICT,
    created_at   TIMESTAMPTZ NOT NULL,
    CHECK (
        (chat_type = 'DIRECT' AND group_name IS NULL)
        OR
        (chat_type = 'GROUP'
         AND group_name IS NOT NULL
         AND length(btrim(group_name)) > 0)
    )
);

CREATE TABLE chat_members (
    chat_id    BIGINT NOT NULL
               REFERENCES chats(chat_id) ON DELETE CASCADE,
    user_id    BIGINT NOT NULL
               REFERENCES users(user_id) ON DELETE RESTRICT,
    role       TEXT NOT NULL CHECK (role IN ('ADMIN', 'MEMBER')),
    joined_at  TIMESTAMPTZ NOT NULL,
    left_at    TIMESTAMPTZ,
    is_muted   BOOLEAN NOT NULL DEFAULT FALSE,
    PRIMARY KEY (chat_id, user_id),
    CHECK (left_at IS NULL OR left_at >= joined_at)
);

CREATE TABLE media (
    media_id      BIGINT PRIMARY KEY CHECK (media_id > 0),
    uploader_id   BIGINT NOT NULL
                  REFERENCES users(user_id) ON DELETE RESTRICT,
    media_type    TEXT NOT NULL
                  CHECK (media_type IN ('IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT')),
    mime_type     TEXT NOT NULL
                  CHECK (mime_type ~ '^[A-Za-z0-9.+-]+/[A-Za-z0-9.+-]+$'),
    size_bytes    BIGINT NOT NULL CHECK (size_bytes > 0),
    sha256        TEXT NOT NULL CHECK (sha256 ~ '^[0-9a-f]{64}$'),
    uploaded_at   TIMESTAMPTZ NOT NULL
);

CREATE TABLE messages (
    message_id          BIGINT PRIMARY KEY CHECK (message_id > 0),
    chat_id             BIGINT NOT NULL
                        REFERENCES chats(chat_id) ON DELETE RESTRICT,
    sender_id           BIGINT NOT NULL
                        REFERENCES users(user_id) ON DELETE RESTRICT,
    sent_at             TIMESTAMPTZ NOT NULL,
    message_type        TEXT NOT NULL
                        CHECK (message_type IN
                               ('TEXT', 'LOCATION', 'IMAGE', 'VIDEO',
                                'AUDIO', 'DOCUMENT')),
    body                TEXT,
    media_id            BIGINT
                        REFERENCES media(media_id) ON DELETE RESTRICT,
    reply_to_message_id BIGINT
                        REFERENCES messages(message_id) ON DELETE SET NULL,
    is_forwarded        BOOLEAN NOT NULL DEFAULT FALSE,
    is_deleted          BOOLEAN NOT NULL DEFAULT FALSE,
    edited_at           TIMESTAMPTZ,
    CHECK (reply_to_message_id IS NULL OR reply_to_message_id <> message_id),
    CHECK (edited_at IS NULL OR edited_at >= sent_at),
    CHECK (message_type NOT IN ('TEXT', 'LOCATION') OR media_id IS NULL),
    CHECK (
        is_deleted
        OR message_type NOT IN ('IMAGE', 'VIDEO', 'AUDIO', 'DOCUMENT')
        OR media_id IS NOT NULL
    ),
    CHECK (
        is_deleted
        OR message_type NOT IN ('TEXT', 'LOCATION')
        OR body IS NOT NULL
    )
);

CREATE TABLE message_receipts (
    message_id    BIGINT NOT NULL
                  REFERENCES messages(message_id) ON DELETE CASCADE,
    user_id       BIGINT NOT NULL
                  REFERENCES users(user_id) ON DELETE RESTRICT,
    delivered_at  TIMESTAMPTZ,
    read_at       TIMESTAMPTZ,
    PRIMARY KEY (message_id, user_id),
    CHECK (
        read_at IS NULL
        OR (delivered_at IS NOT NULL AND read_at >= delivered_at)
    )
);

CREATE TABLE calls (
    call_id      BIGINT PRIMARY KEY CHECK (call_id > 0),
    chat_id      BIGINT NOT NULL
                 REFERENCES chats(chat_id) ON DELETE RESTRICT,
    caller_id    BIGINT NOT NULL
                 REFERENCES users(user_id) ON DELETE RESTRICT,
    call_type    TEXT NOT NULL CHECK (call_type IN ('VOICE', 'VIDEO')),
    started_at   TIMESTAMPTZ NOT NULL,
    answered_at  TIMESTAMPTZ,
    ended_at     TIMESTAMPTZ,
    status       TEXT NOT NULL
                 CHECK (status IN ('COMPLETED', 'FAILED', 'MISSED', 'REJECTED')),
    CHECK (answered_at IS NULL OR answered_at >= started_at),
    CHECK (ended_at IS NULL OR ended_at >= started_at),
    CHECK (answered_at IS NULL OR ended_at IS NULL OR ended_at >= answered_at),
    CHECK (
        status <> 'COMPLETED'
        OR (answered_at IS NOT NULL AND ended_at IS NOT NULL)
    )
);

CREATE TABLE blocked_users (
    blocker_id  BIGINT NOT NULL
                REFERENCES users(user_id) ON DELETE CASCADE,
    blocked_id  BIGINT NOT NULL
                REFERENCES users(user_id) ON DELETE CASCADE,
    blocked_at  TIMESTAMPTZ NOT NULL,
    PRIMARY KEY (blocker_id, blocked_id),
    CHECK (blocker_id <> blocked_id)
);

COMMIT;
