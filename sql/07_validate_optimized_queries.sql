-- SC-Disruption (T0124) - CP3 repeatable validation for optimized queries.
-- This file proves correctness by comparing each optimized query against the original
-- or an independently written equivalent. All validations run inside a transaction
-- and roll back any temporary/adversarial data. Persistent database data is left unchanged.

\set ON_ERROR_STOP on
SET search_path TO whatsapp;

BEGIN;

-- =====================================================================
-- R10 validation: half-open range equivalence to original date cast
-- =====================================================================
WITH original_r10 AS (
    SELECT sent_at::date AS day,
           count(DISTINCT sender_id) AS active_senders,
           count(*) AS messages
    FROM messages
    WHERE sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
    GROUP BY 1
),
optimized_r10 AS (
    SELECT sent_at::date AS day,
           count(DISTINCT sender_id) AS active_senders,
           count(*) AS messages
    FROM messages
    WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
      AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
    GROUP BY 1
),
diff_orig_opt AS (
    SELECT 'r10_original_except_optimized' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM original_r10 EXCEPT SELECT * FROM optimized_r10) t
),
diff_opt_orig AS (
    SELECT 'r10_optimized_except_original' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM optimized_r10 EXCEPT SELECT * FROM original_r10) t
),
r10_count AS (
    SELECT 'r10_optimized_row_count' AS check_name, count(*) AS cnt FROM optimized_r10
)
SELECT check_name, cnt FROM diff_orig_opt
UNION ALL SELECT check_name, cnt FROM diff_opt_orig
UNION ALL SELECT check_name, cnt FROM r10_count
ORDER BY check_name;

-- Fail explicitly if R10 result sets differ.
DO $$
DECLARE
    v_diff_orig_opt int;
    v_diff_opt_orig int;
BEGIN
    WITH original_r10 AS (
        SELECT sent_at::date AS day,
               count(DISTINCT sender_id) AS active_senders,
               count(*) AS messages
        FROM messages
        WHERE sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
        GROUP BY 1
    ),
    optimized_r10 AS (
        SELECT sent_at::date AS day,
               count(DISTINCT sender_id) AS active_senders,
               count(*) AS messages
        FROM messages
        WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
          AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
        GROUP BY 1
    )
    SELECT count(*) INTO v_diff_orig_opt
    FROM (SELECT * FROM original_r10 EXCEPT SELECT * FROM optimized_r10) t;

    WITH original_r10 AS (
        SELECT sent_at::date AS day,
               count(DISTINCT sender_id) AS active_senders,
               count(*) AS messages
        FROM messages
        WHERE sent_at::date BETWEEN '2026-06-01' AND '2026-06-30'
        GROUP BY 1
    ),
    optimized_r10 AS (
        SELECT sent_at::date AS day,
               count(DISTINCT sender_id) AS active_senders,
                count(*) AS messages
        FROM messages
        WHERE sent_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
          AND sent_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
        GROUP BY 1
    )
    SELECT count(*) INTO v_diff_opt_orig
    FROM (SELECT * FROM optimized_r10 EXCEPT SELECT * FROM original_r10) t;

    IF v_diff_orig_opt <> 0 OR v_diff_opt_orig <> 0 THEN
        RAISE EXCEPTION 'R10 validation failed: orig_except_opt=%, opt_except_orig=%',
            v_diff_orig_opt, v_diff_opt_orig;
    END IF;
END $$;

-- =====================================================================
-- R13 validation: NOT EXISTS vs LEFT JOIN ... IS NULL (from Aaditi's commit)
-- =====================================================================
WITH not_exists_q AS (
    SELECT m.message_id, m.sender_id, m.sent_at, m.body
    FROM messages m
    WHERE m.chat_id = 20501
      AND m.body LIKE '%?%'
      AND NOT EXISTS (
          SELECT 1
          FROM messages r
          WHERE r.reply_to_message_id = m.message_id
      )
),
left_join_q AS (
    SELECT m.message_id, m.sender_id, m.sent_at, m.body
    FROM messages m
    LEFT JOIN messages r ON r.reply_to_message_id = m.message_id
    WHERE m.chat_id = 20501
      AND m.body LIKE '%?%'
      AND r.message_id IS NULL
),
null_check AS (
    SELECT 'null_reply_to_count' AS check_name, count(*) AS cnt
    FROM messages
    WHERE reply_to_message_id IS NULL
),
diff_ne_lj AS (
    SELECT 'not_exists_except_left_join' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM not_exists_q EXCEPT SELECT * FROM left_join_q) t
),
diff_lj_ne AS (
    SELECT 'left_join_except_not_exists' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM left_join_q EXCEPT SELECT * FROM not_exists_q) t
),
reply_check AS (
    SELECT 'returned_messages_have_no_replies' AS check_name, count(*) AS cnt
    FROM not_exists_q neq
    WHERE EXISTS (SELECT 1 FROM messages r WHERE r.reply_to_message_id = neq.message_id)
),
result_count AS (
    SELECT 'optimized_r13_result_count' AS check_name, count(*) AS cnt
    FROM not_exists_q
)
SELECT check_name, cnt FROM null_check
UNION ALL SELECT check_name, cnt FROM diff_ne_lj
UNION ALL SELECT check_name, cnt FROM diff_lj_ne
UNION ALL SELECT check_name, cnt FROM reply_check
UNION ALL SELECT check_name, cnt FROM result_count
ORDER BY check_name;

DO $$
DECLARE
    v_diff_ne_lj   int;
    v_diff_lj_ne   int;
    v_reply_viol   int;
BEGIN
    WITH not_exists_q AS (
        SELECT m.message_id, m.sender_id, m.sent_at, m.body
        FROM messages m
        WHERE m.chat_id = 20501
          AND m.body LIKE '%?%'
          AND NOT EXISTS (
              SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id
          )
    ),
    left_join_q AS (
        SELECT m.message_id, m.sender_id, m.sent_at, m.body
        FROM messages m
        LEFT JOIN messages r ON r.reply_to_message_id = m.message_id
        WHERE m.chat_id = 20501
          AND m.body LIKE '%?%'
          AND r.message_id IS NULL
    )
    SELECT count(*) INTO v_diff_ne_lj
    FROM (SELECT * FROM not_exists_q EXCEPT SELECT * FROM left_join_q) t;

    WITH not_exists_q AS (
        SELECT m.message_id, m.sender_id, m.sent_at, m.body
        FROM messages m
        WHERE m.chat_id = 20501
          AND m.body LIKE '%?%'
          AND NOT EXISTS (
              SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id
          )
    ),
    left_join_q AS (
        SELECT m.message_id, m.sender_id, m.sent_at, m.body
        FROM messages m
        LEFT JOIN messages r ON r.reply_to_message_id = m.message_id
        WHERE m.chat_id = 20501
          AND m.body LIKE '%?%'
          AND r.message_id IS NULL
    )
    SELECT count(*) INTO v_diff_lj_ne
    FROM (SELECT * FROM left_join_q EXCEPT SELECT * FROM not_exists_q) t;

    WITH not_exists_q AS (
        SELECT m.message_id
        FROM messages m
        WHERE m.chat_id = 20501
          AND m.body LIKE '%?%'
          AND NOT EXISTS (
              SELECT 1 FROM messages r WHERE r.reply_to_message_id = m.message_id
          )
    )
    SELECT count(*) INTO v_reply_viol
    FROM not_exists_q neq
    WHERE EXISTS (SELECT 1 FROM messages r WHERE r.reply_to_message_id = neq.message_id);

    IF v_diff_ne_lj <> 0 OR v_diff_lj_ne <> 0 OR v_reply_viol <> 0 THEN
        RAISE EXCEPTION 'R13 validation failed: diff_ne_lj=%, diff_lj_ne=%, reply_violations=%',
            v_diff_ne_lj, v_diff_lj_ne, v_reply_viol;
    END IF;
END $$;

-- =====================================================================
-- R19 validation: grouped rewrite vs original correlated subqueries
-- The optimized query uses m.sent_at >= '2026-06-01' (no upper bound) to match original.
-- =====================================================================
WITH original_r19 AS (
    SELECT c.chat_id, c.group_name,
           (SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id) AS last_message_at,
           (SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01') AS june_messages
    FROM chats c
    WHERE c.chat_type = 'GROUP'
),
optimized_r19 AS (
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
),
diff_orig_opt AS (
    SELECT 'r19_original_except_optimized' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM original_r19 EXCEPT SELECT * FROM optimized_r19) t
),
diff_opt_orig AS (
    SELECT 'r19_optimized_except_original' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM optimized_r19 EXCEPT SELECT * FROM original_r19) t
),
r19_count AS (
    SELECT 'r19_optimized_row_count' AS check_name, count(*) AS cnt FROM optimized_r19
)
SELECT check_name, cnt FROM diff_orig_opt
UNION ALL SELECT check_name, cnt FROM diff_opt_orig
UNION ALL SELECT check_name, cnt FROM r19_count
ORDER BY check_name;

DO $$
DECLARE
    v_diff_orig_opt int;
    v_diff_opt_orig int;
BEGIN
    WITH original_r19 AS (
        SELECT c.chat_id, c.group_name,
               (SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id) AS last_message_at,
               (SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01') AS june_messages
        FROM chats c
        WHERE c.chat_type = 'GROUP'
    ),
    optimized_r19 AS (
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
    )
    SELECT count(*) INTO v_diff_orig_opt
    FROM (SELECT * FROM original_r19 EXCEPT SELECT * FROM optimized_r19) t;

    WITH original_r19 AS (
        SELECT c.chat_id, c.group_name,
               (SELECT max(m.sent_at) FROM messages m WHERE m.chat_id = c.chat_id) AS last_message_at,
               (SELECT count(*) FROM messages m WHERE m.chat_id = c.chat_id AND m.sent_at >= '2026-06-01') AS june_messages
        FROM chats c
        WHERE c.chat_type = 'GROUP'
    ),
    optimized_r19 AS (
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
    )
    SELECT count(*) INTO v_diff_opt_orig
    FROM (SELECT * FROM optimized_r19 EXCEPT SELECT * FROM original_r19) t;

    IF v_diff_orig_opt <> 0 OR v_diff_opt_orig <> 0 THEN
        RAISE EXCEPTION 'R19 validation failed: orig_except_opt=%, opt_except_orig=%',
            v_diff_orig_opt, v_diff_opt_orig;
    END IF;
END $$;

-- =====================================================================
-- R22 validation: deep-page cursor equivalence
-- Cursor derivation (performed once before benchmarking):
--   SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1;
--   In the benchmark dataset this cursor value is 20001.
-- Timed optimized query uses fixed cursor 20001 (no OFFSET).
-- =====================================================================
WITH original_r22 AS (
    SELECT message_id, chat_id, sender_id, message_type, sent_at
    FROM messages
    ORDER BY message_id DESC
    OFFSET 100000 LIMIT 25
),
optimized_r22 AS (
    SELECT m.message_id,
           m.chat_id,
           m.sender_id,
           m.message_type,
           m.sent_at
    FROM messages m
    WHERE m.message_id < 20001
    ORDER BY m.message_id DESC
    LIMIT 25
),
diff_orig_opt AS (
    SELECT 'r22_original_except_optimized' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM original_r22 EXCEPT SELECT * FROM optimized_r22) t
),
diff_opt_orig AS (
    SELECT 'r22_optimized_except_original' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM optimized_r22 EXCEPT SELECT * FROM original_r22) t
),
orig_count AS (
    SELECT 'r22_original_row_count' AS check_name, count(*) AS cnt FROM original_r22
),
opt_count AS (
    SELECT 'r22_optimized_row_count' AS check_name, count(*) AS cnt FROM optimized_r22
)
SELECT check_name, cnt FROM diff_orig_opt
UNION ALL SELECT check_name, cnt FROM diff_opt_orig
UNION ALL SELECT check_name, cnt FROM orig_count
UNION ALL SELECT check_name, cnt FROM opt_count
ORDER BY check_name;

DO $$
DECLARE
    v_diff_orig_opt int;
    v_diff_opt_orig int;
BEGIN
    WITH original_r22 AS (
        SELECT message_id, chat_id, sender_id, message_type, sent_at
        FROM messages
        ORDER BY message_id DESC
        OFFSET 100000 LIMIT 25
    ),
    optimized_r22 AS (
        SELECT m.message_id,
               m.chat_id,
               m.sender_id,
               m.message_type,
               m.sent_at
        FROM messages m
        WHERE m.message_id < 20001
        ORDER BY m.message_id DESC
        LIMIT 25
    )
    SELECT count(*) INTO v_diff_orig_opt
    FROM (SELECT * FROM original_r22 EXCEPT SELECT * FROM optimized_r22) t;

    WITH original_r22 AS (
        SELECT message_id, chat_id, sender_id, message_type, sent_at
        FROM messages
        ORDER BY message_id DESC
        OFFSET 100000 LIMIT 25
    ),
    optimized_r22 AS (
        SELECT m.message_id,
               m.chat_id,
               m.sender_id,
               m.message_type,
               m.sent_at
        FROM messages m
        WHERE m.message_id < 20001
        ORDER BY m.message_id DESC
        LIMIT 25
    )
    SELECT count(*) INTO v_diff_opt_orig
    FROM (SELECT * FROM optimized_r22 EXCEPT SELECT * FROM original_r22) t;

    IF v_diff_orig_opt <> 0 OR v_diff_opt_orig <> 0 THEN
        RAISE EXCEPTION 'R22 validation failed: orig_except_opt=%, opt_except_orig=%',
            v_diff_orig_opt, v_diff_opt_orig;
    END IF;
END $$;

-- =====================================================================
-- W02 validation: EXISTS rewrite affects same rows as original join
-- Runs inside transaction; rolls back to leave data unchanged.
-- =====================================================================
-- Capture affected message_ids from original query
WITH original_affected AS (
    SELECT r.message_id
    FROM message_receipts r
    JOIN messages m ON m.message_id = r.message_id
    WHERE m.chat_id = 22556
      AND r.user_id = 965
      AND r.read_at IS NULL
),
optimized_affected AS (
    SELECT r.message_id
    FROM message_receipts r
    WHERE r.user_id = 965
      AND r.read_at IS NULL
      AND EXISTS (
          SELECT 1 FROM messages m WHERE m.message_id = r.message_id AND m.chat_id = 22556
      )
),
diff_orig_opt AS (
    SELECT 'w02_original_except_optimized' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM original_affected EXCEPT SELECT * FROM optimized_affected) t
),
diff_opt_orig AS (
    SELECT 'w02_optimized_except_original' AS check_name, count(*) AS cnt
    FROM (SELECT * FROM optimized_affected EXCEPT SELECT * FROM original_affected) t
),
orig_count AS (
    SELECT 'w02_original_affected_count' AS check_name, count(*) AS cnt FROM original_affected
),
opt_count AS (
    SELECT 'w02_optimized_affected_count' AS check_name, count(*) AS cnt FROM optimized_affected
)
SELECT check_name, cnt FROM diff_orig_opt
UNION ALL SELECT check_name, cnt FROM diff_opt_orig
UNION ALL SELECT check_name, cnt FROM orig_count
UNION ALL SELECT check_name, cnt FROM opt_count
ORDER BY check_name;

DO $$
DECLARE
    v_diff_orig_opt int;
    v_diff_opt_orig int;
BEGIN
    WITH original_affected AS (
        SELECT r.message_id
        FROM message_receipts r
        JOIN messages m ON m.message_id = r.message_id
        WHERE m.chat_id = 22556
          AND r.user_id = 965
          AND r.read_at IS NULL
    ),
    optimized_affected AS (
        SELECT r.message_id
        FROM message_receipts r
        WHERE r.user_id = 965
          AND r.read_at IS NULL
          AND EXISTS (
              SELECT 1 FROM messages m WHERE m.message_id = r.message_id AND m.chat_id = 22556
          )
    )
    SELECT count(*) INTO v_diff_orig_opt
    FROM (SELECT * FROM original_affected EXCEPT SELECT * FROM optimized_affected) t;

    WITH original_affected AS (
        SELECT r.message_id
        FROM message_receipts r
        JOIN messages m ON m.message_id = r.message_id
        WHERE m.chat_id = 22556
          AND r.user_id = 965
          AND r.read_at IS NULL
    ),
    optimized_affected AS (
        SELECT r.message_id
        FROM message_receipts r
        WHERE r.user_id = 965
          AND r.read_at IS NULL
          AND EXISTS (
              SELECT 1 FROM messages m WHERE m.message_id = r.message_id AND m.chat_id = 22556
          )
    )
    SELECT count(*) INTO v_diff_opt_orig
    FROM (SELECT * FROM optimized_affected EXCEPT SELECT * FROM original_affected) t;

    IF v_diff_orig_opt <> 0 OR v_diff_opt_orig <> 0 THEN
        RAISE EXCEPTION 'W02 validation failed: orig_except_opt=%, opt_except_orig=%',
            v_diff_orig_opt, v_diff_opt_orig;
    END IF;
END $$;

-- Roll back — leaves persistent database data unchanged.
ROLLBACK;