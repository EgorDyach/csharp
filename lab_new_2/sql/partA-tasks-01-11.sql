-- ============================================================================
-- Лабораторная работа №2. Когда индексов недостаточно
-- Часть A. Задания 1-11 — исследование роста данных
--
-- Таблица events наращивается по контрольным точкам 10k -> 100k -> 1M -> 5M -> 10M.
-- На каждой точке снимаются: размер, план без индекса, план с индексом.
-- Индекс после замера удаляется, чтобы следующая точка снова начиналась
-- с честного «без индекса».
--
-- Запуск:
--   docker exec chakchakshop_postgres psql -U postgres -c "DROP DATABASE IF EXISTS lab_scaling;"
--   docker exec chakchakshop_postgres psql -U postgres -c "CREATE DATABASE lab_scaling;"
--   docker exec -i chakchakshop_postgres psql -U postgres -d lab_scaling -X -f - < partA-tasks-01-11.sql
-- ============================================================================

\echo ''
\echo '================================================================'
\echo ' ОКРУЖЕНИЕ'
\echo '================================================================'
SELECT current_setting('server_version') AS postgres_version;
SELECT name, setting, unit FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','effective_cache_size',
               'random_page_cost','max_parallel_workers_per_gather')
ORDER BY name;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 1. Создание таблицы events'
\echo '================================================================'
DROP TABLE IF EXISTS events;
CREATE TABLE events (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload JSONB,
    created_at TIMESTAMP NOT NULL
);

-- Функция генерации порции данных: вызывается на каждой контрольной точке.
CREATE OR REPLACE FUNCTION gen_events(n BIGINT) RETURNS void AS $$
BEGIN
    INSERT INTO events (user_id, event_type, payload, created_at)
    SELECT
        (random() * 100000)::bigint,
        CASE
            WHEN random() < 0.4 THEN 'MESSAGE'
            WHEN random() < 0.7 THEN 'LOGIN'
            WHEN random() < 0.9 THEN 'PURCHASE'
            ELSE 'OTHER'
        END,
        '{}'::jsonb,
        NOW() - (random() * INTERVAL '365 days')
    FROM generate_series(1, n);
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- КОНТРОЛЬНАЯ ТОЧКА 1: 10 000 строк
-- ============================================================================
\echo ''
\echo '################################################################'
\echo '#  КОНТРОЛЬНАЯ ТОЧКА: 10 000 строк'
\echo '################################################################'
SELECT gen_events(10000);
ANALYZE events;

\echo '--- ЗАДАНИЕ 3. Размер таблицы ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('events'))       AS table_size,
       pg_size_pretty(pg_total_relation_size('events')) AS total_size
FROM events;

\echo '--- ЗАДАНИЕ 4. SELECT без дополнительного индекса ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo '--- ЗАДАНИЕ 5. Тот же запрос с индексом ---'
CREATE INDEX idx_events_user_id ON events(user_id);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_id')) AS index_size;
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;
DROP INDEX idx_events_user_id;

-- ============================================================================
-- КОНТРОЛЬНАЯ ТОЧКА 2: 100 000 строк
-- ============================================================================
\echo ''
\echo '################################################################'
\echo '#  КОНТРОЛЬНАЯ ТОЧКА: 100 000 строк'
\echo '################################################################'
SELECT gen_events(90000);
ANALYZE events;

\echo '--- ЗАДАНИЕ 3. Размер таблицы ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('events'))       AS table_size,
       pg_size_pretty(pg_total_relation_size('events')) AS total_size
FROM events;

\echo '--- ЗАДАНИЕ 4. SELECT без дополнительного индекса ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo '--- ЗАДАНИЕ 5. Тот же запрос с индексом ---'
CREATE INDEX idx_events_user_id ON events(user_id);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_id')) AS index_size;
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;
DROP INDEX idx_events_user_id;

-- ============================================================================
-- КОНТРОЛЬНАЯ ТОЧКА 3: 1 000 000 строк
-- ============================================================================
\echo ''
\echo '################################################################'
\echo '#  КОНТРОЛЬНАЯ ТОЧКА: 1 000 000 строк'
\echo '################################################################'
SELECT gen_events(900000);
ANALYZE events;

\echo '--- ЗАДАНИЕ 3. Размер таблицы ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('events'))       AS table_size,
       pg_size_pretty(pg_total_relation_size('events')) AS total_size
FROM events;

\echo '--- ЗАДАНИЕ 4. SELECT без дополнительного индекса ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo '--- ЗАДАНИЕ 5. Тот же запрос с индексом ---'
CREATE INDEX idx_events_user_id ON events(user_id);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_id')) AS index_size;
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;
DROP INDEX idx_events_user_id;

-- ============================================================================
-- КОНТРОЛЬНАЯ ТОЧКА 4: 5 000 000 строк
-- ============================================================================
\echo ''
\echo '################################################################'
\echo '#  КОНТРОЛЬНАЯ ТОЧКА: 5 000 000 строк'
\echo '################################################################'
SELECT gen_events(4000000);
ANALYZE events;

\echo '--- ЗАДАНИЕ 3. Размер таблицы ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('events'))       AS table_size,
       pg_size_pretty(pg_total_relation_size('events')) AS total_size
FROM events;

\echo '--- ЗАДАНИЕ 4. SELECT без дополнительного индекса ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo '--- ЗАДАНИЕ 5. Тот же запрос с индексом ---'
CREATE INDEX idx_events_user_id ON events(user_id);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_id')) AS index_size;
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;
DROP INDEX idx_events_user_id;

-- ============================================================================
-- КОНТРОЛЬНАЯ ТОЧКА 5: 10 000 000 строк
-- ============================================================================
\echo ''
\echo '################################################################'
\echo '#  КОНТРОЛЬНАЯ ТОЧКА: 10 000 000 строк'
\echo '################################################################'
SELECT gen_events(5000000);
ANALYZE events;

\echo '--- ЗАДАНИЕ 3. Размер таблицы ---'
SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('events'))       AS table_size,
       pg_size_pretty(pg_total_relation_size('events')) AS total_size
FROM events;

\echo '--- ЗАДАНИЕ 4. SELECT без дополнительного индекса ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo '--- ЗАДАНИЕ 5. Тот же запрос с индексом ---'
CREATE INDEX idx_events_user_id ON events(user_id);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_id')) AS index_size;
EXPLAIN ANALYZE SELECT * FROM events WHERE user_id = 123;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM events WHERE user_id = 123;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 6. Поиск по диапазону дат (на 10 000 000 строк)'
\echo '================================================================'
\echo '--- 6.1 ДО индекса по created_at: последние сутки ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '1 day';

CREATE INDEX idx_events_created_at ON events(created_at);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_created_at')) AS index_size;

\echo '--- 6.2 ПОСЛЕ индекса: последние сутки ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '1 day';
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '1 day';

\echo '--- 6.3 сколько строк попадает в разные диапазоны ---'
SELECT '1 day'    AS range, count(*), round(100.0*count(*)/(SELECT count(*) FROM events), 3) AS pct FROM events WHERE created_at >= NOW() - INTERVAL '1 day'
UNION ALL SELECT '7 days',  count(*), round(100.0*count(*)/(SELECT count(*) FROM events), 3) FROM events WHERE created_at >= NOW() - INTERVAL '7 days'
UNION ALL SELECT '30 days', count(*), round(100.0*count(*)/(SELECT count(*) FROM events), 3) FROM events WHERE created_at >= NOW() - INTERVAL '30 days'
UNION ALL SELECT '180 days',count(*), round(100.0*count(*)/(SELECT count(*) FROM events), 3) FROM events WHERE created_at >= NOW() - INTERVAL '180 days';

\echo '--- 6.4 диапазон 7 дней ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '7 days';
\echo '--- 6.5 диапазон 30 дней ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '30 days';
\echo '--- 6.6 диапазон 180 дней (половина таблицы) ---'
EXPLAIN ANALYZE SELECT * FROM events WHERE created_at >= NOW() - INTERVAL '180 days';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 7. Фильтрация и сортировка'
\echo '================================================================'
\echo '--- 7.1 ДО составного индекса ---'
EXPLAIN ANALYZE
SELECT * FROM events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100;

CREATE INDEX idx_events_user_created ON events(user_id, created_at DESC);
ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_user_created')) AS index_size;

\echo '--- 7.2 ПОСЛЕ составного индекса ---'
EXPLAIN ANALYZE
SELECT * FROM events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100;

\echo '--- 7.3 обратный порядок колонок: (created_at, user_id) для сравнения ---'
CREATE INDEX idx_events_created_user ON events(created_at DESC, user_id);
ANALYZE events;
BEGIN;
DROP INDEX idx_events_user_created, idx_events_user_id;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 123 ORDER BY created_at DESC LIMIT 100;
ROLLBACK;
DROP INDEX idx_events_created_user;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 8. Агрегация'
\echo '================================================================'
\echo '--- 8.1 GROUP BY event_type за 30 дней (индекс по created_at есть) ---'
EXPLAIN ANALYZE
SELECT event_type, COUNT(*) FROM events
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY event_type;
EXPLAIN (ANALYZE, BUFFERS)
SELECT event_type, COUNT(*) FROM events
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY event_type;

\echo '--- 8.2 та же агрегация с принудительно отключённым индексом ---'
SET enable_indexscan = off;
SET enable_bitmapscan = off;
EXPLAIN ANALYZE
SELECT event_type, COUNT(*) FROM events
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY event_type;
RESET ALL;

\echo '--- 8.3 агрегация без ограничения по дате (вся таблица) ---'
EXPLAIN ANALYZE
SELECT event_type, COUNT(*) FROM events GROUP BY event_type;

\echo '--- 8.4 поможет ли покрывающий индекс (created_at, event_type)? ---'
CREATE INDEX idx_events_created_type ON events(created_at, event_type);
VACUUM ANALYZE events;
SELECT pg_size_pretty(pg_relation_size('idx_events_created_type')) AS covering_index_size;
EXPLAIN (ANALYZE, BUFFERS)
SELECT event_type, COUNT(*) FROM events
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY event_type;
DROP INDEX idx_events_created_type;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 9. Стоимость индексов при записи'
\echo '================================================================'
\echo 'Замер на отдельной таблице той же структуры, чтобы не искажать events.'
DROP TABLE IF EXISTS events_bench_plain;
DROP TABLE IF EXISTS events_bench_indexed;
CREATE TABLE events_bench_plain   (LIKE events INCLUDING DEFAULTS);
CREATE TABLE events_bench_indexed (LIKE events INCLUDING DEFAULTS);

CREATE INDEX bench_idx_user_id    ON events_bench_indexed(user_id);
CREATE INDEX bench_idx_created_at ON events_bench_indexed(created_at);
CREATE INDEX bench_idx_user_crea  ON events_bench_indexed(user_id, created_at DESC);

\echo '--- 9.1 INSERT 500 000 строк БЕЗ индексов ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
INSERT INTO events_bench_plain (user_id, event_type, payload, created_at)
SELECT (random() * 100000)::bigint,
       CASE WHEN random() < 0.4 THEN 'MESSAGE' WHEN random() < 0.7 THEN 'LOGIN'
            WHEN random() < 0.9 THEN 'PURCHASE' ELSE 'OTHER' END,
       '{}'::jsonb,
       NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 500000);

\echo '--- 9.2 INSERT 500 000 строк С ТРЕМЯ индексами ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
INSERT INTO events_bench_indexed (user_id, event_type, payload, created_at)
SELECT (random() * 100000)::bigint,
       CASE WHEN random() < 0.4 THEN 'MESSAGE' WHEN random() < 0.7 THEN 'LOGIN'
            WHEN random() < 0.9 THEN 'PURCHASE' ELSE 'OTHER' END,
       '{}'::jsonb,
       NOW() - (random() * INTERVAL '365 days')
FROM generate_series(1, 500000);

\echo '--- 9.3 сколько занимают данные и сколько индексы ---'
SELECT relname,
       pg_size_pretty(pg_relation_size(oid))       AS heap,
       pg_size_pretty(pg_indexes_size(oid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(oid)) AS total
FROM pg_class
WHERE relname IN ('events_bench_plain','events_bench_indexed','events')
ORDER BY relname;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 10. Размер индексов на 10 000 000 строк'
\echo '================================================================'
SELECT indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS index_size,
       idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE relname = 'events'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT pg_size_pretty(pg_relation_size('events'))       AS heap,
       pg_size_pretty(pg_indexes_size('events'))        AS all_indexes,
       pg_size_pretty(pg_total_relation_size('events')) AS total;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 11. Когда индекс уже не спасает'
\echo '================================================================'
\echo '--- 11.1 GROUP BY DATE(created_at) за 365 дней — вся таблица ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE(created_at), COUNT(*)
FROM events
WHERE created_at >= NOW() - INTERVAL '365 days'
GROUP BY DATE(created_at);

\echo '--- 11.2 то же самое, но за 7 дней: селективное условие ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT DATE(created_at), COUNT(*)
FROM events
WHERE created_at >= NOW() - INTERVAL '7 days'
GROUP BY DATE(created_at);

\echo '--- 11.3 решение из мира больших данных: предагрегированная витрина ---'
DROP TABLE IF EXISTS events_daily;
CREATE TABLE events_daily AS
SELECT DATE(created_at) AS day, event_type, COUNT(*) AS cnt
FROM events
GROUP BY DATE(created_at), event_type;
CREATE UNIQUE INDEX idx_events_daily ON events_daily(day, event_type);
ANALYZE events_daily;

SELECT count(*) AS rows_in_rollup,
       pg_size_pretty(pg_total_relation_size('events_daily')) AS rollup_size,
       pg_size_pretty(pg_total_relation_size('events'))       AS source_size
FROM events_daily;

\echo '--- 11.4 тот же отчёт по витрине вместо сырой таблицы ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT day, SUM(cnt) FROM events_daily
WHERE day >= (NOW() - INTERVAL '365 days')::date
GROUP BY day;
