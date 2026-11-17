# Schema design — SC-Disruption (T0124)

## Method and verified result

The schema was inferred from all nine CSV headers, observed nulls, domain
values and relationships. It was then created in a fresh PostgreSQL 15.18
database and loaded without editing any seed row.

| Table | Expected rows | Loaded rows |
|---|---:|---:|
| users | 30,000 | 30,000 |
| devices | 42,000 | 42,000 |
| chats | 23,000 | 23,000 |
| chat_members | 104,514 | 104,514 |
| media | 27,634 | 27,634 |
| messages | 120,000 | 120,000 |
| message_receipts | 501,590 | 501,590 |
| calls | 25,000 | 25,000 |
| blocked_users | 4,000 | 4,000 |

Total rows loaded: **877,738**. The run used an empty local database named
sc_disruption_cp1_20261117. Both SQL files completed with ON_ERROR_STOP, so a
constraint or COPY failure would have stopped the test.

## Data dictionary

PK means primary key, FK means foreign key, UK means unique and NN means not
null. Executable details are in sql/01_schema.sql.

### users

| Column | Type | Constraints | Why |
|---|---|---|---|
| user_id | bigint | PK, positive | Stable account identifier with growth headroom |
| phone_e164 | text | NN, UK, E.164-format check | A phone is an identifier, not a number used in arithmetic |
| display_name | text | NN, nonblank | Required user-facing name; names are not unique |
| about | text | nullable | 11,949 users have no profile text |
| is_business | boolean | NN, default false | Exact two-state export value |
| joined_on | date | NN | Signup is recorded as a calendar date |
| last_seen_at | timestamptz | nullable | Privacy/offline state leaves 624 values absent |
| status | text | NN, ACTIVE/BANNED/DELETED | Controlled account lifecycle |

### devices

| Column | Type | Constraints | Why |
|---|---|---|---|
| device_id | bigint | PK, positive | Stable device identifier |
| user_id | bigint | NN, FK users, cascade delete | A device belongs to one account |
| device_type | text | NN, allowed four values | Prevents invalid platform codes |
| app_version | text | NN, dotted-version check | Versions are labels rather than decimals |
| registered_at | timestamptz | NN | Registration instant is required |
| last_active_at | timestamptz | NN, not before registration | Supports stale-device cleanup |

### chats

| Column | Type | Constraints | Why |
|---|---|---|---|
| chat_id | bigint | PK, positive | Stable conversation identifier |
| chat_type | text | NN, DIRECT/GROUP | Determines conversation rules |
| group_name | text | nullable, conditional check | NULL for all direct chats; nonblank for groups |
| created_by | bigint | NN, FK users, restrict delete | Preserves creator history |
| created_at | timestamptz | NN | Required creation instant |

### chat_members

| Column | Type | Constraints | Why |
|---|---|---|---|
| chat_id | bigint | composite PK, FK chats, cascade delete | Membership belongs to a chat |
| user_id | bigint | composite PK, FK users, restrict delete | One current/history row per user-chat pair |
| role | text | NN, ADMIN/MEMBER | Controlled group permission |
| joined_at | timestamptz | NN | Required membership start |
| left_at | timestamptz | nullable, not before join | NULL means still a member |
| is_muted | boolean | NN, default false | Per-member notification preference |

### media

| Column | Type | Constraints | Why |
|---|---|---|---|
| media_id | bigint | PK, positive | Stable upload identifier |
| uploader_id | bigint | NN, FK users, restrict delete | Preserves upload ownership |
| media_type | text | NN, four-value domain | Matches supported media categories |
| mime_type | text | NN, MIME-shape check | Stores the actual file format |
| size_bytes | bigint | NN, positive | Large files require integer growth headroom |
| sha256 | text | NN, 64 lowercase hex characters | Hash is a string and duplicates are meaningful |
| uploaded_at | timestamptz | NN | Required upload instant |

### messages

| Column | Type | Constraints | Why |
|---|---|---|---|
| message_id | bigint | PK, positive | Stable message identifier |
| chat_id | bigint | NN, FK chats, restrict delete | Every message belongs to one chat |
| sender_id | bigint | NN, FK users, restrict delete | Preserves sender history |
| sent_at | timestamptz | NN | Ordering and time-range queries need the instant |
| message_type | text | NN, six-value domain | Supports text, location and four media types |
| body | text | nullable, conditionally required | Absent for media and deleted content; required for live text/location |
| media_id | bigint | nullable, FK media, restrict delete | Required for live media; absent for text/location |
| reply_to_message_id | bigint | nullable, self-FK, not self | Optional reply chain; parent deletion sets it NULL |
| is_forwarded | boolean | NN, default false | Forwarding signal for abuse analysis |
| is_deleted | boolean | NN, default false | Logical deletion keeps history |
| edited_at | timestamptz | nullable, not before sent_at | NULL means never edited |

### message_receipts

| Column | Type | Constraints | Why |
|---|---|---|---|
| message_id | bigint | composite PK, FK messages, cascade delete | Receipt belongs to one message |
| user_id | bigint | composite PK, FK users, restrict delete | One receipt state per recipient/message |
| delivered_at | timestamptz | nullable | NULL means not delivered |
| read_at | timestamptz | nullable, requires delivery and follows it | NULL means unread |

### calls

| Column | Type | Constraints | Why |
|---|---|---|---|
| call_id | bigint | PK, positive | Stable call identifier |
| chat_id | bigint | NN, FK chats, restrict delete | Call occurs in one chat |
| caller_id | bigint | NN, FK users, restrict delete | Preserves caller history |
| call_type | text | NN, VOICE/VIDEO | Controlled call mode |
| started_at | timestamptz | NN | Call start is always known |
| answered_at | timestamptz | nullable, not before start | Missing for unanswered calls |
| ended_at | timestamptz | nullable, follows start/answer | Missing while unfinished; present for completed calls |
| status | text | NN, four-value domain; completed requires answer/end | Controls call lifecycle |

### blocked_users

| Column | Type | Constraints | Why |
|---|---|---|---|
| blocker_id | bigint | composite PK, FK users, cascade delete | Directed relationship source |
| blocked_id | bigint | composite PK, FK users, cascade delete, differs from blocker | Directed relationship target; self-block is invalid |
| blocked_at | timestamptz | NN | Records when the active block began |

## Keys, deletion rules and cardinality

- users.phone_e164 is the only natural alternate key. Display names and SHA-256
  values are deliberately non-unique.
- chat_members, message_receipts and blocked_users use two-column primary
  keys because their facts depend on both referenced entities.
- Users and chats are many-to-many through chat_members. Users and messages
  are many-to-many through message_receipts.
- One user can own many devices, create many chats, upload many files, send
  many messages and initiate many calls.
- One chat can contain many memberships, messages and calls. One message can
  have many receipts and replies, but at most one parent and one media row.
- CASCADE is used for tightly owned rows: devices of a physically removed
  user, memberships of a removed chat, receipts of a removed message, and
  block edges. RESTRICT protects historical creators, participants, uploads,
  senders, chats and callers. Account removal should normally use
  status = DELETED instead of a physical delete.
- Deleting a parent message sets a child's reply pointer to NULL so the child
  remains valid.

The editable cardinality diagram is diagrams/er_diagram.mmd. Rendered PNG and
SVG versions are committed beside it.

## Null rules and observations

- group_name is NULL for all 20,000 direct chats and present for all 3,000
  groups.
- left_at is NULL for 98,213 active memberships.
- delivered_at is NULL for 5,076 pending deliveries; read_at is NULL for
  129,242 unread receipts.
- answered_at is absent for missed/rejected/failed calls where nobody
  answered. ended_at can be absent for a call without a recorded end.
- body and media_id depend on message type. LOCATION behaves like TEXT: it has
  body content and no media row.
- reply_to_message_id is NULL for messages that are not replies. edited_at is
  NULL for messages never edited.
- The export contains 2,340 deleted messages; all have body and media cleared.
  The constraint still permits a deleted row to retain content temporarily
  because is_deleted describes lifecycle state, while clearing may be a
  separate operation.

## Integrity-check results

The following checks were run after the full load:

| Check | Violations |
|---|---:|
| Message sender has no membership row for its chat | 0 |
| Reply points to a message in a different chat | 0 |
| Direct chat has other than exactly two membership rows | 0 |
| Receipt read time is before message send time | 0 |
| Linked media type differs from message type | 0 |

These checks validate the seed export. Cross-table facts such as exactly two
members in every future direct chat or a reply staying within the same chat
cannot be enforced with an ordinary row CHECK; application transactions or
future constraint triggers should enforce them.

### Queries used for the integrity review

The zero-violation results above are reproducible with these checks:

    SELECT count(*) AS sender_without_membership
    FROM whatsapp.messages m
    WHERE NOT EXISTS (
        SELECT 1
        FROM whatsapp.chat_members cm
        WHERE cm.chat_id = m.chat_id
          AND cm.user_id = m.sender_id
    );

    SELECT count(*) AS reply_in_different_chat
    FROM whatsapp.messages child
    JOIN whatsapp.messages parent
      ON parent.message_id = child.reply_to_message_id
    WHERE child.chat_id <> parent.chat_id;

    SELECT count(*) AS direct_chat_member_count_not_two
    FROM (
        SELECT c.chat_id
        FROM whatsapp.chats c
        LEFT JOIN whatsapp.chat_members cm ON cm.chat_id = c.chat_id
        WHERE c.chat_type = 'DIRECT'
        GROUP BY c.chat_id
        HAVING count(cm.user_id) <> 2
    ) AS invalid_direct_chats;

    SELECT count(*) AS receipt_read_before_message_sent
    FROM whatsapp.message_receipts r
    JOIN whatsapp.messages m USING (message_id)
    WHERE r.read_at < m.sent_at;

    SELECT count(*) AS media_message_type_mismatch
    FROM whatsapp.messages m
    JOIN whatsapp.media md USING (media_id)
    WHERE m.message_type <> md.media_type;

The diagram uses crow's-foot cardinality. A circle means optional/zero, a bar
means one, and the fork means many. The two associative relations
chat_members and message_receipts resolve the two many-to-many relationships.

## Functional dependencies and normal forms

| Relation | Main functional dependencies | Normal-form conclusion |
|---|---|---|
| users | user_id → all attributes; phone_e164 → all attributes | BCNF |
| devices | device_id → user_id, type, version and timestamps | BCNF |
| chats | chat_id → type, name, creator, created_at | BCNF |
| chat_members | (chat_id, user_id) → role, joined_at, left_at, is_muted | BCNF for one row per pair |
| media | media_id → uploader, type, MIME, size, hash, uploaded_at | BCNF under upload identity |
| messages | message_id → every message attribute | BCNF |
| message_receipts | (message_id, user_id) → delivered_at, read_at | BCNF |
| calls | call_id → all call attributes | BCNF |
| blocked_users | (blocker_id, blocked_id) → blocked_at | BCNF |

Every field is atomic, satisfying 1NF. The three composite-key tables have no
attribute that depends on only part of the key, satisfying 2NF. Under the
listed dependencies, no non-key attribute determines another non-key
attribute, so the tables satisfy 3NF; every determinant shown is a candidate
key, so they are BCNF under these business assumptions.

The current seed happens to contain one MIME value per media type, but that
sample correlation is not treated as a permanent functional dependency:
IMAGE can later include PNG, WebP or other formats. media.media_type describes
the upload; messages.message_type describes message behavior, including TEXT
and LOCATION, so retaining both is justified and their agreement is checked.
Member count, unread count and call duration are derived rather than stored,
avoiding update anomalies.

The composite membership key cannot represent multiple leave/rejoin episodes
for the same user and chat. If that history becomes required, a membership
episode identifier or joined_at in the key would be needed.

## Baseline indexes

CP1 adds no tuning index. PostgreSQL created only ten indexes required by
constraints: nine primary-key indexes plus the unique phone_e164 index.
PostgreSQL does not automatically index foreign-key columns. This preserves
an untuned baseline for CP2.

## Reproduction

From the repository root:

    unzip -n seed_data.zip
    createdb sc_disruption_seed
    psql -X -v ON_ERROR_STOP=1 -d sc_disruption_seed -f sql/01_schema.sql
    psql -X -v ON_ERROR_STOP=1 -d sc_disruption_seed -f sql/02_load_data.sql

The seed_data directory is ignored by Git and must not be committed.
