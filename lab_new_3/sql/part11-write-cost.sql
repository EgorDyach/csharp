-- =====================================================================
-- Часть 12, дополнение: во что партиционирование обходится записи
-- =====================================================================
-- Партиционирование обычно продают как ускорение чтения. У записи своя
-- цена: на каждую строку PostgreSQL определяет партицию (tuple routing),
-- а планировщик держит в памяти описание десятков таблиц.
--
-- Чтобы эффект был чистым, обе таблицы создаются заново и с одинаковым
-- набором индексов. Боевая orders в опыте не участвует.
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = lab3, public;
SET TIME ZONE 'UTC';

DROP TABLE IF EXISTS lab3.w_plain CASCADE;
DROP TABLE IF EXISTS lab3.w_part  CASCADE;

\echo '### W0 Две одинаковые таблицы: обычная и разбитая на 25 месячных партиций'
CREATE TABLE lab3.w_plain (
    id           uuid          NOT NULL,
    user_id      uuid          NOT NULL,
    total_amount numeric(18,2) NOT NULL,
    status       varchar(50)   NOT NULL,
    created_at   timestamptz   NOT NULL
);

CREATE TABLE lab3.w_part (LIKE lab3.w_plain) PARTITION BY RANGE (created_at);
DO $$
DECLARE d date := date '2024-09-01';
BEGIN
    WHILE d < date '2026-10-01' LOOP
        EXECUTE format('CREATE TABLE lab3.%I PARTITION OF lab3.w_part FOR VALUES FROM (%L) TO (%L)',
                       'w_part_' || to_char(d, 'YYYY_MM'), d, d + INTERVAL '1 month');
        d := (d + INTERVAL '1 month')::date;
    END LOOP;
END $$;

-- Одинаковые индексы с обеих сторон, иначе сравнение бессмысленно
CREATE INDEX ON lab3.w_plain (created_at DESC);
CREATE INDEX ON lab3.w_plain (user_id, created_at DESC);
CREATE INDEX ON lab3.w_part  (created_at DESC);
CREATE INDEX ON lab3.w_part  (user_id, created_at DESC);

CREATE TEMP TABLE w_src AS
SELECT gen_random_uuid() AS id,
       gen_random_uuid() AS user_id,
       round((random() * 5000)::numeric, 2) AS total_amount,
       'Completed'::varchar(50) AS status,
       '2024-10-01'::timestamptz + (random() * 700) * INTERVAL '1 day' AS created_at
FROM generate_series(1, 500000);
ANALYZE w_src;

\echo '### W1 500 000 строк в ОБЫЧНУЮ таблицу'
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO lab3.w_plain SELECT * FROM w_src;

\echo '### W2 Те же 500 000 строк в ПАРТИЦИОНИРОВАННУЮ (25 партиций)'
EXPLAIN (ANALYZE, BUFFERS)
INSERT INTO lab3.w_part SELECT * FROM w_src;

\echo '### W3 Размер: одна таблица против двадцати пяти'
SELECT 'w_plain' AS t, pg_size_pretty(pg_total_relation_size('lab3.w_plain')) AS total
UNION ALL
SELECT 'w_part', pg_size_pretty(sum(pg_total_relation_size(inhrelid)))
FROM pg_inherits WHERE inhparent = 'lab3.w_part'::regclass;

\echo '### W4 Цена планирования: 1 таблица против 25 партиций'
ANALYZE lab3.w_plain;
ANALYZE lab3.w_part;
EXPLAIN (ANALYZE) SELECT count(*) FROM lab3.w_plain WHERE created_at >= '2025-05-01' AND created_at < '2025-06-01';
EXPLAIN (ANALYZE) SELECT count(*) FROM lab3.w_part  WHERE created_at >= '2025-05-01' AND created_at < '2025-06-01';

\echo '### W5 И то, ради чего всё затевалось: удаление старого месяца'
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM lab3.w_plain WHERE created_at >= '2024-10-01' AND created_at < '2024-11-01';
DROP TABLE lab3.w_part_2024_10;
