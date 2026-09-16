-- =====================================================================
-- Часть 12, шаг 6 (ДО): базовые замеры реальных запросов API
--                       на непартиционированной таблице orders
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = public;
SET TIME ZONE 'UTC';

\echo '### 12.0 Исходное состояние таблицы'
SELECT count(*) AS rows,
       pg_size_pretty(pg_total_relation_size('orders')) AS total_size,
       min(created_at), max(created_at)
FROM orders;

\d orders

-- Берём существующий заказ, чтобы запрос GET /orders/{id} был честным
SELECT id AS order_id, user_id AS uid, created_at
FROM orders ORDER BY created_at DESC LIMIT 1 \gset

\echo '### 12.1 Q1: GET /api/orders?from=2026-07-01&to=2026-08-01 (страница за период)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders
WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;

\echo '### 12.2 Q2: GET /api/orders/{id}'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE id = :'order_id';

\echo '### 12.3 Q3: GET /api/orders/statistics?from=2026-07-01&to=2026-08-01'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_at) AS day,
       count(*)                      AS orders_count,
       sum(total_amount)             AS revenue
FROM orders
WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01'
GROUP BY 1 ORDER BY 1;

\echo '### 12.4 Q4: GET /api/orders/my (страница заказов клиента)'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM orders WHERE user_id = :'uid'
ORDER BY created_at DESC LIMIT 20 OFFSET 0;

\echo '### 12.5 Годовая аналитика: сколько данных реально приходится трогать'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount) FROM orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';

\echo '### 12.6 Удаление данных старше двух лет на обычной таблице'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM orders WHERE created_at < '2024-10-01';
