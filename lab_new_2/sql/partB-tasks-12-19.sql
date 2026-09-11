-- ============================================================================
-- Лабораторная работа №2. Часть B. Задания 12-19 — собственный сервис
-- Проект: ChakChakShop, база chakchakshop, сущность orders
--
-- Таблица наращивается 1M -> 3M -> 5M заказов, на каждом объёме снимаются
-- одни и те же четыре запроса. Индексы — те, что добавлены миграцией
-- 004-performance-indexes.sql по итогам лабораторной работы №1.
--
-- Запуск:
--   docker exec -i chakchakshop_postgres psql -U postgres -d chakchakshop -X -f - \
--     < partB-tasks-12-19.sql
-- ============================================================================

\set HOT_USER 'aaaaaaaa-0000-0000-0000-000000000003'

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 12. Выбор сущности'
\echo '================================================================'
SELECT relname AS table_name,
       n_live_tup AS approx_rows,
       pg_size_pretty(pg_relation_size(relid))       AS heap,
       pg_size_pretty(pg_indexes_size(relid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_stat_user_tables
WHERE relname IN ('orders','order_items','users','products')
ORDER BY pg_total_relation_size(relid) DESC;

\echo '--- индексы, доступные запросам (после миграции 004) ---'
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'orders' ORDER BY indexname;

-- Обычный клиент — для запроса «поиск по внешнему ключу».
-- Берём его из самой таблицы orders: случайный пользователь из users мог
-- вообще не получить заказов при генерации, и замер вышел бы на пустой выборке.
SELECT user_id AS regular_user
FROM orders
WHERE user_id <> 'aaaaaaaa-0000-0000-0000-000000000003'
ORDER BY id
LIMIT 1 \gset

\echo '--- сколько заказов у выбранных пользователей ---'
SELECT 'обычный клиент' AS who, count(*) FROM orders WHERE user_id = :'regular_user'
UNION ALL
SELECT 'крупный клиент', count(*) FROM orders WHERE user_id = :'HOT_USER';

-- ============================================================================
-- Функция наращивания объёма: 95% заказов случайным клиентам, 5% крупному.
-- created_at привязан к диапазону уже существующих данных, иначе новые заказы
-- оказались бы самыми свежими и исказили запросы «за последние N дней».
-- ============================================================================
CREATE OR REPLACE FUNCTION grow_orders(n BIGINT) RETURNS void AS $$
DECLARE
    anchor TIMESTAMPTZ;
BEGIN
    SELECT max(created_at) INTO anchor FROM orders;

    INSERT INTO orders (id, user_id, total_amount, status, created_at, updated_at)
    SELECT gen_random_uuid(),
           CASE WHEN random() < 0.05
                THEN 'aaaaaaaa-0000-0000-0000-000000000003'::uuid
                ELSE u.id END,
           round((random() * 9000 + 450)::numeric, 2),
           (ARRAY['Pending','Processing','Completed','Cancelled','Refunded'])[floor(random() * 5 + 1)::INT],
           anchor - (random() * INTERVAL '2 years'),
           NULL
    FROM generate_series(1, n) g
    JOIN LATERAL (
        SELECT id FROM users WHERE username LIKE 'loadtest_user_%'
        OFFSET floor(random() * 50000) LIMIT 1
    ) u ON TRUE;
END;
$$ LANGUAGE plpgsql;

-- ============================================================================
-- ЗАМЕРЫ. Один и тот же блок из четырёх запросов на каждом объёме.
-- ============================================================================

\echo ''
\echo '################################################################'
\echo '#  ОБЪЁМ 1: 1 000 000 заказов (baseline, ЗАДАНИЕ 14)'
\echo '################################################################'
ANALYZE orders;
SELECT count(*) AS orders_rows,
       pg_size_pretty(pg_relation_size('orders')) AS heap,
       pg_size_pretty(pg_indexes_size('orders'))  AS indexes
FROM orders;

\echo '--- Query 1: поиск по внешнему ключу (обычный клиент) ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';

\echo '--- Query 2: диапазон дат (последние 7 дней) ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';

\echo '--- Query 3: фильтр + сортировка + LIMIT (личный кабинет крупного клиента) ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;

\echo '--- Query 4: админский отчёт — агрегация по статусам за 30 дней ---'
EXPLAIN ANALYZE SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;
EXPLAIN (ANALYZE, BUFFERS) SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;

\echo ''
\echo '################################################################'
\echo '#  ЗАДАНИЕ 15. Наращивание до 3 000 000 заказов'
\echo '################################################################'
SELECT grow_orders(2000000);
VACUUM ANALYZE orders;
SELECT count(*) AS orders_rows,
       pg_size_pretty(pg_relation_size('orders')) AS heap,
       pg_size_pretty(pg_indexes_size('orders'))  AS indexes
FROM orders;

\echo '--- Query 1 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';

\echo '--- Query 2 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';

\echo '--- Query 3 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;

\echo '--- Query 4 ---'
EXPLAIN ANALYZE SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;
EXPLAIN (ANALYZE, BUFFERS) SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;

\echo ''
\echo '################################################################'
\echo '#  ЗАДАНИЕ 15. Наращивание до 5 000 000 заказов'
\echo '################################################################'
SELECT grow_orders(2000000);
VACUUM ANALYZE orders;
SELECT count(*) AS orders_rows,
       pg_size_pretty(pg_relation_size('orders')) AS heap,
       pg_size_pretty(pg_indexes_size('orders'))  AS indexes
FROM orders;

\echo '--- Query 1 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'regular_user';

\echo '--- Query 2 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE created_at >= NOW() - INTERVAL '7 days';

\echo '--- Query 3 ---'
EXPLAIN ANALYZE SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;
EXPLAIN (ANALYZE, BUFFERS) SELECT id, user_id, total_amount, status, created_at, updated_at
  FROM orders WHERE user_id = :'HOT_USER' ORDER BY created_at DESC LIMIT 50;

\echo '--- Query 4 ---'
EXPLAIN ANALYZE SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;
EXPLAIN (ANALYZE, BUFFERS) SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 17. Узкое место: сколько строк обрабатывает каждый запрос'
\echo '================================================================'
SELECT 'Query 1 (user_id обычного клиента)' AS query, count(*) AS rows_processed FROM orders WHERE user_id = :'regular_user'
UNION ALL SELECT 'Query 2 (7 дней)',   count(*) FROM orders WHERE created_at >= NOW() - INTERVAL '7 days'
UNION ALL SELECT 'Query 3 (крупный клиент, всего)', count(*) FROM orders WHERE user_id = :'HOT_USER'
UNION ALL SELECT 'Query 4 (30 дней)',  count(*) FROM orders WHERE created_at >= NOW() - INTERVAL '30 days';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 18. Попытки улучшить самый тяжёлый запрос (Query 4)'
\echo '================================================================'
\echo '--- 18.1 покрывающий индекс (created_at, status) INCLUDE (total_amount) ---'
CREATE INDEX "IX_orders_created_at_status_incl"
    ON orders (created_at DESC, status) INCLUDE (total_amount);
VACUUM ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('"IX_orders_created_at_status_incl"')) AS covering_index_size;

EXPLAIN ANALYZE SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;
EXPLAIN (ANALYZE, BUFFERS) SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '30 days' GROUP BY status;

\echo '--- 18.2 сужаем окно отчёта до 1 дня: тот же запрос, меньше данных ---'
EXPLAIN (ANALYZE, BUFFERS) SELECT status, COUNT(*), SUM(total_amount)
  FROM orders WHERE created_at >= NOW() - INTERVAL '1 day' GROUP BY status;

\echo '--- 18.3 предагрегированная витрина вместо сырой таблицы ---'
DROP TABLE IF EXISTS orders_daily_stats;
CREATE TABLE orders_daily_stats AS
SELECT date_trunc('day', created_at)::date AS day,
       status,
       COUNT(*)          AS orders_count,
       SUM(total_amount) AS revenue
FROM orders
GROUP BY 1, 2;
CREATE UNIQUE INDEX "IX_orders_daily_stats" ON orders_daily_stats (day, status);
ANALYZE orders_daily_stats;

SELECT count(*) AS rows_in_rollup,
       pg_size_pretty(pg_total_relation_size('orders_daily_stats')) AS rollup_size,
       pg_size_pretty(pg_total_relation_size('orders'))             AS source_size
FROM orders_daily_stats;

EXPLAIN (ANALYZE, BUFFERS)
SELECT status, SUM(orders_count), SUM(revenue)
FROM orders_daily_stats
WHERE day >= (NOW() - INTERVAL '30 days')::date
GROUP BY status;

\echo '--- 18.4 удаляем covering-индекс, если он не окупился ---'
DROP INDEX "IX_orders_created_at_status_incl";

\echo ''
\echo '================================================================'
\echo ' ИТОГ: размеры после роста до 5 млн заказов'
\echo '================================================================'
SELECT indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan AS times_used
FROM pg_stat_user_indexes WHERE relname = 'orders'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT pg_size_pretty(pg_relation_size('orders'))       AS heap,
       pg_size_pretty(pg_indexes_size('orders'))        AS all_indexes,
       pg_size_pretty(pg_total_relation_size('orders')) AS total;
