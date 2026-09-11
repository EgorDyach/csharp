-- =====================================================================
-- Часть 12, шаг 6 (ПОСЛЕ): те же запросы API на партиционированной
--                          таблице orders_partitioned
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = public;
SET TIME ZONE 'UTC';

SELECT id AS order_id, user_id AS uid
FROM public.orders ORDER BY created_at DESC LIMIT 1 \gset

\echo '### 12.14 Q1: GET /api/orders?from=2026-07-01&to=2026-08-01'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM public.orders_partitioned
WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01'
ORDER BY created_at DESC
LIMIT 20 OFFSET 0;

\echo '### 12.15 Q2: GET /api/orders/{id} — pruning НЕ работает'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM public.orders_partitioned WHERE id = :'order_id';

\echo '### 12.16 Q2-fix: тот же запрос с датой заказа в условии'
--      если клиент передаёт дату (она есть в ссылке из списка), pruning вернётся
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM public.orders_partitioned
WHERE id = :'order_id'
  AND created_at >= '2026-09-01' AND created_at < '2026-10-01';

\echo '### 12.17 Q3: GET /api/orders/statistics?from=2026-07-01&to=2026-08-01'
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_at) AS day,
       count(*)                      AS orders_count,
       sum(total_amount)             AS revenue
FROM public.orders_partitioned
WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01'
GROUP BY 1 ORDER BY 1;

\echo '### 12.18 Q4: GET /api/orders/my — pruning частичный'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM public.orders_partitioned WHERE user_id = :'uid'
ORDER BY created_at DESC LIMIT 20 OFFSET 0;

\echo '### 12.19 Q4-fix: у списка заказов клиента почти всегда есть период'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, total_amount, status, created_at, updated_at
FROM public.orders_partitioned
WHERE user_id = :'uid'
  AND created_at >= '2026-07-01' AND created_at < '2026-10-01'
ORDER BY created_at DESC LIMIT 20 OFFSET 0;

\echo '### 12.20 Годовая аналитика: 12 партиций из 26'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount) FROM public.orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';

\echo '### 12.21 Планирование: цена большого числа партиций'
EXPLAIN (ANALYZE)
SELECT count(*) FROM public.orders_partitioned;

\echo '### 12.22 Сколько партиций реально прочитано (pg_stat_user_tables)'
SELECT relname, seq_scan, idx_scan
FROM pg_stat_user_tables
WHERE schemaname = 'public' AND relname LIKE 'orders_p_%'
ORDER BY relname;
