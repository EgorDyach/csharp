-- ============================================================================
-- Лабораторная работа №1. Индексы и EXPLAIN ANALYZE в PostgreSQL
-- Часть 1. Задания 1-10 (тестовая база данных)
--
-- Запуск:
--   docker exec chakchakshop_postgres psql -U postgres -c "DROP DATABASE IF EXISTS lab_indexes;"
--   docker exec chakchakshop_postgres psql -U postgres -c "CREATE DATABASE lab_indexes;"
--   docker exec -i chakchakshop_postgres psql -U postgres -d lab_indexes -X -f - < part1-tasks-01-10.sql
-- ============================================================================

\echo ''
\echo '================================================================'
\echo ' ОКРУЖЕНИЕ'
\echo '================================================================'
SELECT current_setting('server_version') AS postgres_version;
SELECT name, setting, unit FROM pg_settings
WHERE name IN ('shared_buffers','work_mem','effective_cache_size',
               'random_page_cost','seq_page_cost','max_parallel_workers_per_gather')
ORDER BY name;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 1. Создание таблицы orders'
\echo '================================================================'
DROP TABLE IF EXISTS orders;
CREATE TABLE orders (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL,
    product_id BIGINT NOT NULL,
    status VARCHAR(20) NOT NULL,
    amount NUMERIC(10, 2) NOT NULL,
    created_at TIMESTAMP NOT NULL,
    updated_at TIMESTAMP NOT NULL
);

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 2. Генерация 1 000 000 записей'
\echo '================================================================'
INSERT INTO orders (user_id, product_id, status, amount, created_at, updated_at)
SELECT
    (random() * 100000)::BIGINT,
    (random() * 10000)::BIGINT,
    -- floor() возвращает double precision, индекс массива требует integer -> ::INT
    (ARRAY['NEW','PAID','DELIVERED','CANCELLED'])[floor(random() * 4 + 1)::INT],
    random() * 10000,
    NOW() - (random() * INTERVAL '2 years'),
    NOW()
FROM generate_series(1, 1000000);

ANALYZE orders;

SELECT count(*) AS rows,
       pg_size_pretty(pg_relation_size('orders'))       AS heap_size,
       pg_size_pretty(pg_total_relation_size('orders')) AS total_size
FROM orders;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 3. EXPLAIN (план без выполнения), индексов ещё нет'
\echo '================================================================'
EXPLAIN
SELECT * FROM orders WHERE user_id = 123;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 4. EXPLAIN ANALYZE (реальное выполнение)'
\echo '================================================================'
\echo '--- прогрев кэша ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 5. Sequential Scan'
\echo '================================================================'
\echo '--- 5a. SELECT * FROM orders (без WHERE) ---'
EXPLAIN ANALYZE SELECT * FROM orders;
\echo '--- 5b. WHERE amount > 0 (условие есть, но отсекает 0 строк) ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE amount > 0;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 6. Первый B-tree индекс по user_id'
\echo '================================================================'
CREATE INDEX idx_orders_user_id ON orders(user_id);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_user_id')) AS index_size;

\echo '--- прогрев ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;
\echo '--- замер (после индекса) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 7. Индекс по status и низкая селективность'
\echo '================================================================'
CREATE INDEX idx_orders_status ON orders(status);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_status')) AS index_size;

\echo '--- status = PAID ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'PAID';
\echo '--- status = NEW ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'NEW';
\echo '--- status = DELIVERED ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'DELIVERED';
\echo '--- status = CANCELLED ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'CANCELLED';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 8. Селективность'
\echo '================================================================'
\echo '--- распределение значений status ---'
SELECT status,
       COUNT(*) AS rows,
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct_of_table
FROM orders
GROUP BY status
ORDER BY 2 DESC;

\echo '--- 8.1 высокая селективность: user_id = 123 (~0.001% таблицы) ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123;

\echo '--- 8.2 средняя селективность: 25% таблицы (status = PAID) ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PAID';

\echo '--- 8.3 те же 25%, но планировщику запрещён индекс: сравнение стоимости ---'
SET enable_bitmapscan = off;
SET enable_indexscan  = off;
EXPLAIN ANALYZE SELECT * FROM orders WHERE status = 'PAID';
RESET ALL;

\echo '--- 8.4 низкая селективность: 50% таблицы ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status IN ('PAID','NEW');

\echo '--- 8.5 очень низкая селективность: 75% таблицы -> планировщик уходит в Seq Scan ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE status <> 'PAID';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 9. Range Query по created_at'
\echo '================================================================'
\echo '--- 9.1 ДО индекса: created_at > NOW() - 7 days ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';

CREATE INDEX idx_orders_created_at ON orders(created_at);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_created_at')) AS index_size;

\echo '--- 9.2 ПОСЛЕ индекса: сколько строк попадает в каждый диапазон ---'
SELECT '1 day'   AS range, count(*) AS rows, round(100.0*count(*)/1000000, 3) AS pct FROM orders WHERE created_at > NOW() - INTERVAL '1 day'
UNION ALL SELECT '7 days',  count(*), round(100.0*count(*)/1000000, 3) FROM orders WHERE created_at > NOW() - INTERVAL '7 days'
UNION ALL SELECT '1 month', count(*), round(100.0*count(*)/1000000, 3) FROM orders WHERE created_at > NOW() - INTERVAL '1 month'
UNION ALL SELECT '1 year',  count(*), round(100.0*count(*)/1000000, 3) FROM orders WHERE created_at > NOW() - INTERVAL '1 year';

\echo '--- 9.3 INTERVAL 1 day ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 day';
\echo '--- 9.4 INTERVAL 7 days ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '7 days';
\echo '--- 9.5 INTERVAL 1 month ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 month';
\echo '--- 9.6 INTERVAL 1 year ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '1 year';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 10. Bitmap Index Scan / Bitmap Heap Scan'
\echo '================================================================'
\echo '--- 10.1 средний объём выборки: status = NEW ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE status = 'NEW';

\echo '--- 10.2 для сравнения: точечный поиск -> Bitmap по 10 строкам ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 123;

\echo '--- 10.3 amount BETWEEN 1000 AND 3000 (индекса по amount нет) ---'
SELECT count(*) AS rows_matched FROM orders WHERE amount BETWEEN 1000 AND 3000;
EXPLAIN ANALYZE SELECT * FROM orders WHERE amount BETWEEN 1000 AND 3000;

\echo '--- 10.4 BitmapAnd: пересечение двух индексов ---'
EXPLAIN ANALYZE
SELECT * FROM orders
WHERE user_id BETWEEN 1000 AND 2000
  AND created_at > NOW() - INTERVAL '1 month';

\echo ''
\echo '================================================================'
\echo ' ИТОГ: индексы, созданные в заданиях 1-10'
\echo '================================================================'
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY indexrelname;

SELECT pg_size_pretty(pg_relation_size('orders'))  AS heap,
       pg_size_pretty(pg_indexes_size('orders'))   AS all_indexes;
