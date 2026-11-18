-- SC-Disruption (T0124) - CP3 repeatable validation for optimized queries.
-- This file proves R13 correctness by comparing the NOT EXISTS anti-join
-- against an independently written LEFT JOIN ... IS NULL anti-join.
-- It runs inside a transaction and rolls back any temporary/adversarial data.
-- Persistent database data is left unchanged.

\set ON_ERROR_STOP on
SET search_path TO whatsapp;

BEGIN;

-- Run all validation checks and report results.
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

-- Fail explicitly if any invariant is violated (re-evaluate inside DO block).
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

-- Roll back — leaves persistent database data unchanged.
ROLLBACK;