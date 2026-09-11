-- ============================================================================
-- Лабораторная работа №1. Часть 3. Задания 22-29 — собственный сервис
-- Проект: ChakChakShop (ASP.NET Core 8 + PostgreSQL + Dapper/EF Core)
-- База: chakchakshop
--
-- Скрипт приводит базу к состоянию «как в проекте» (только те индексы,
-- которые создаёт EF Core), снимает baseline, затем добавляет индексы
-- из миграции 004-performance-indexes.sql и повторяет замеры.
--
-- Запуск:
--   docker exec -i chakchakshop_postgres psql -U postgres -d chakchakshop -X -f - \
--     < part3-service-tasks-22-29.sql
-- ============================================================================

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 22. Scaling Entity: таблица orders'
\echo '================================================================'
SELECT relname AS table_name,
       n_live_tup AS approx_rows,
       pg_size_pretty(pg_relation_size(relid))       AS heap,
       pg_size_pretty(pg_indexes_size(relid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(relid)) AS total
FROM pg_stat_user_tables
WHERE relname IN ('orders','order_items','users','products')
ORDER BY pg_total_relation_size(relid) DESC;

\echo '--- распределение заказов по пользователям ---'
SELECT count(*) AS total_orders,
       count(DISTINCT user_id) AS distinct_users,
       round(count(*)::numeric / count(DISTINCT user_id), 1) AS avg_orders_per_user,
       max(cnt) AS max_orders_per_user
FROM orders, LATERAL (SELECT count(*) AS cnt FROM orders o2 WHERE o2.user_id = orders.user_id LIMIT 1) x;

\echo '--- распределение по статусам ---'
SELECT status, count(*),
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM orders GROUP BY status ORDER BY 2 DESC;

\echo ''
\echo '================================================================'
\echo ' ПРИВЕДЕНИЕ К СОСТОЯНИЮ «КАК В ПРОЕКТЕ»'
\echo '================================================================'
\echo 'EF Core создаёт для orders только PK и индекс по внешнему ключу user_id.'
DROP INDEX IF EXISTS "IX_orders_user_id_created_at";
DROP INDEX IF EXISTS "IX_orders_created_at";
DROP INDEX IF EXISTS "IX_orders_user_id_status_created_at";
ANALYZE orders;
ANALYZE order_items;

SELECT indexname, indexdef FROM pg_indexes
WHERE tablename = 'orders' ORDER BY indexname;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 25. Существующие индексы и статистика их использования'
\echo '================================================================'
SELECT s.relname, s.indexrelname, s.idx_scan,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size,
       i.indisunique AS is_unique
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.relname IN ('orders','order_items','users')
ORDER BY s.idx_scan DESC, s.relname;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 23-24. Реальные запросы сервиса и baseline'
\echo '================================================================'

\echo ''
\echo '### Query 1 — GET /api/orders/my'
\echo '### DapperOrderRepository.GetByUserIdAsync'
\echo '### SELECT ... FROM orders WHERE user_id = @UserId ORDER BY created_at DESC'
\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' ORDER BY created_at DESC;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' ORDER BY created_at DESC;

\echo ''
\echo '### Query 2 — GET /api/orders/{id}'
\echo '### DapperOrderRepository.GetOrderWithItemsAsync (два запроса)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE id = 'bbbbbbbb-0000-0000-0000-000000000001';

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, order_id, product_id, quantity, unit_price, total_price
FROM order_items WHERE order_id = 'bbbbbbbb-0000-0000-0000-000000000001';

\echo ''
\echo '### Query 3 — GET /api/orders (список для админа)'
\echo '### DapperOrderRepository.GetAllAsync — пагинация выполняется В ПАМЯТИ приложения'
\echo '### SELECT ... FROM orders ORDER BY created_at DESC   -- без LIMIT!'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders ORDER BY created_at DESC;

\echo ''
\echo '### Query 4 — «мои заказы в статусе X», фильтрация + сортировка + LIMIT'
\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' AND status = 'Completed'
ORDER BY created_at DESC LIMIT 20;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' AND status = 'Completed'
ORDER BY created_at DESC LIMIT 20;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 26-27. Узкое место и что с ним делать'
\echo '================================================================'
\echo 'Query 3 читает всю таблицу целиком, потому что LIMIT/OFFSET выполняются'
\echo 'в C#-коде (orders.Skip().Take()), а не в SQL. Проверяем, что даёт'
\echo 'перенос пагинации в запрос ДО добавления индекса:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders ORDER BY created_at DESC LIMIT 10 OFFSET 0;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 28. Применение миграции 004-performance-indexes.sql'
\echo '================================================================'
CREATE INDEX IF NOT EXISTS "IX_orders_user_id_created_at"
    ON orders (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS "IX_orders_created_at"
    ON orders (created_at DESC);

ANALYZE orders;

SELECT indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY pg_relation_size(indexrelid) DESC;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 29. Повторное измерение'
\echo '================================================================'

\echo ''
\echo '### Query 1 ПОСЛЕ — без LIMIT (как сейчас в коде)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' ORDER BY created_at DESC;

\echo ''
\echo '### Query 1 ПОСЛЕ — с серверной пагинацией (исправленный код)'
\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003'
ORDER BY created_at DESC LIMIT 20 OFFSET 0;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003'
ORDER BY created_at DESC LIMIT 20 OFFSET 0;

\echo ''
\echo '### Query 3 ПОСЛЕ — индекс + серверная пагинация'
\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders ORDER BY created_at DESC LIMIT 10 OFFSET 0;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders ORDER BY created_at DESC LIMIT 10 OFFSET 0;

\echo ''
\echo '### Query 3 — глубокая страница: цена OFFSET'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders ORDER BY created_at DESC LIMIT 10 OFFSET 10000;

\echo ''
\echo '### COUNT(*) для поля TotalCount в PagedResponse'
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM orders;

\echo ''
\echo '### Query 4 ПОСЛЕ — проверяем, нужен ли отдельный индекс по status'
\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' AND status = 'Completed'
ORDER BY created_at DESC LIMIT 20;
\echo '--- замер ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' AND status = 'Completed'
ORDER BY created_at DESC LIMIT 20;

\echo ''
\echo '--- контрольная проверка: окупился бы третий индекс (user_id, status, created_at)? ---'
CREATE INDEX "IX_orders_user_id_status_created_at"
    ON orders (user_id, status, created_at DESC);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('"IX_orders_user_id_status_created_at"')) AS third_index_size;

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE user_id = 'aaaaaaaa-0000-0000-0000-000000000003' AND status = 'Completed'
ORDER BY created_at DESC LIMIT 20;

\echo 'Выигрыш не окупает 40+ MB и замедление записи — индекс удаляем,'
\echo 'в миграцию он не попадает.'
DROP INDEX "IX_orders_user_id_status_created_at";

\echo ''
\echo '================================================================'
\echo ' ИТОГОВОЕ СОСТОЯНИЕ ИНДЕКСОВ ПОСЛЕ МИГРАЦИИ'
\echo '================================================================'
SELECT indexrelname,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT pg_size_pretty(pg_relation_size('orders')) AS heap,
       pg_size_pretty(pg_indexes_size('orders'))  AS all_indexes;
