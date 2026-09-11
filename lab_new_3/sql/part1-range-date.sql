-- =====================================================================
-- Лабораторная работа №3. Часть 1-2: RANGE PARTITIONING по дате
--                                    и partition pruning
-- =====================================================================
-- Учебные таблицы живут в отдельной схеме lab3, чтобы не конфликтовать
-- с боевыми таблицами сервиса (products/orders уже есть в public).
\timing on
\set ON_ERROR_STOP off

CREATE SCHEMA IF NOT EXISTS lab3;
SET search_path = lab3, public;

-- ВАЖНО: имя таблицы всегда квалифицируем схемой. Полагаться на search_path
-- в DROP нельзя: если объекта нет в lab3, PostgreSQL найдёт одноимённый
-- объект в public и удалит боевую таблицу.
DROP TABLE IF EXISTS lab3.events CASCADE;

\echo '### 1.1 Создание партиционированной таблицы'
CREATE TABLE lab3.events (
    id         BIGINT      NOT NULL,
    user_id    BIGINT      NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload    TEXT,
    created_at TIMESTAMP   NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE lab3.events_2026_09_09 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-09') TO ('2026-09-10');
CREATE TABLE lab3.events_2026_09_10 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-10') TO ('2026-09-11');
CREATE TABLE lab3.events_2026_09_11 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-11') TO ('2026-09-12');

\echo '### 1.2 Как это выглядит в каталоге'
SELECT c.relname                          AS partition_name,
       pg_get_expr(c.relpartbound, c.oid) AS bounds
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
WHERE i.inhparent = 'lab3.events'::regclass
ORDER BY 1;

\echo '### 1.3 Загрузка тестовых данных: по 1 000 000 событий на каждый день'
INSERT INTO lab3.events (id, user_id, event_type, payload, created_at)
SELECT g,
       (floor(random() * 100000) + 1)::bigint,
       (ARRAY['click','view','purchase','signup','logout'])[floor(random() * 5 + 1)::int],
       'payload-' || g,
       '2026-09-09'::timestamp + (random() * 3) * INTERVAL '1 day'
FROM generate_series(1, 3000000) g;

ANALYZE lab3.events;

\echo '### 1.4 Проверка распределения по партициям (tableoid::regclass)'
SELECT tableoid::regclass AS partition_name,
       COUNT(*)
FROM events
GROUP BY tableoid
ORDER BY partition_name;

\echo '### 1.5 Задание: в какую партицию попадёт конкретная запись?'
-- Вопрос 1: created_at = 2026-09-10 12:00:00 -> ожидаем events_2026_09_10
INSERT INTO lab3.events VALUES (900000001, 1, 'probe', 'q1', '2026-09-10 12:00:00');
-- Вопрос 2: created_at = 2026-09-11 00:00:00 -> ожидаем events_2026_09_11
--           (нижняя граница FROM включается)
INSERT INTO lab3.events VALUES (900000002, 1, 'probe', 'q2', '2026-09-11 00:00:00');
-- Контрольная точка: 2026-09-10 23:59:59.999999 -> последняя микросекунда 09-10
INSERT INTO lab3.events VALUES (900000003, 1, 'probe', 'q3', '2026-09-10 23:59:59.999999');

SELECT id, created_at, tableoid::regclass AS landed_in
FROM events
WHERE event_type = 'probe'
ORDER BY id;

\echo '### 1.6 Вопрос 3: что будет при вставке за 2026-09-12 (партиции нет)?'
INSERT INTO lab3.events VALUES (900000004, 1, 'probe', 'q4', '2026-09-12 10:00:00');

\echo '### 1.7 Размеры партиций'
SELECT c.relname,
       pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c
JOIN pg_inherits i ON i.inhrelid = c.oid
WHERE i.inhparent = 'lab3.events'::regclass
ORDER BY 1;

-- =====================================================================
-- Часть 2. Partition pruning
-- =====================================================================
\echo '### 2.1 Запрос ПО ключу партиционирования: pruning должен сработать'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM events
WHERE created_at >= '2026-09-10'
  AND created_at <  '2026-09-11';

\echo '### 2.2 Запрос НЕ по ключу партиционирования: pruning невозможен'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*)
FROM events
WHERE event_type = 'click';

\echo '### 2.3 Тот же запрос по ключу, но со значением, вычисляемым в runtime'
--      (демонстрация runtime pruning: планировщик не знает значение заранее)
PREPARE p_events(timestamp, timestamp) AS
SELECT COUNT(*) FROM events WHERE created_at >= $1 AND created_at < $2;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE p_events('2026-09-10', '2026-09-11');

\echo '### 2.4 Сколько партиций реально существует и сколько прочитано'
SELECT relname, seq_scan, seq_tup_read
FROM pg_stat_user_tables
WHERE schemaname = 'lab3' AND relname LIKE 'events_%'
ORDER BY relname;
