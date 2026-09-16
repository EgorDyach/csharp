-- =====================================================================
-- Часть 12, шаг 6 (честное сравнение)
-- =====================================================================
-- Первые замеры делались на холодном кэше: обычная таблица читала
-- 54 372 страницы с диска, партиционированная — 2 273 из памяти.
-- Чтобы сравнение было корректным, каждый запрос выполняется трижды
-- подряд по одной и той же таблице: первый прогон прогревает
-- shared_buffers, третий и есть результат.
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = public;
SET TIME ZONE 'UTC';

\echo '=== A. Статистика за месяц: ОБЫЧНАЯ таблица (3 прогона) ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;

\echo '=== B. Статистика за месяц: ПАРТИЦИОНИРОВАННАЯ (3 прогона) ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders_partitioned WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders_partitioned WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;
EXPLAIN (ANALYZE, BUFFERS) SELECT date_trunc('day', created_at) d, count(*), sum(total_amount)
FROM public.orders_partitioned WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01' GROUP BY 1;

\echo '=== C. Годовая аналитика: ОБЫЧНАЯ таблица (3 прогона) ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';

\echo '=== D. Годовая аналитика: ПАРТИЦИОНИРОВАННАЯ (3 прогона) ==='
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*), sum(total_amount) FROM public.orders_partitioned
WHERE created_at >= '2025-01-01' AND created_at < '2026-01-01';

\echo '=== E. Поиск по id: ОБЫЧНАЯ / ПАРТИЦИОНИРОВАННАЯ (по 3 прогона) ==='
SELECT id AS oid FROM public.orders ORDER BY created_at DESC LIMIT 1 \gset
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders WHERE id = :'oid';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders WHERE id = :'oid';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders WHERE id = :'oid';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders_partitioned WHERE id = :'oid';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders_partitioned WHERE id = :'oid';
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM public.orders_partitioned WHERE id = :'oid';

\echo '=== F. Удаление данных старше двух лет ==='
-- Обычная таблица: DELETE с последующим VACUUM
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM public.orders WHERE created_at < '2024-10-01';
-- Партиционированная: DROP одной партиции
SELECT pg_size_pretty(pg_total_relation_size('public.orders_p_2024_09')) AS partition_to_drop,
       (SELECT count(*) FROM public.orders_p_2024_09)                    AS rows_to_drop;
DROP TABLE public.orders_p_2024_09;
-- Партиция удалена целиком; каталог сразу это видит:
SELECT count(*) AS partitions_left
FROM pg_inherits WHERE inhparent = 'public.orders_partitioned'::regclass;
SELECT count(*) AS rows_left FROM public.orders_partitioned;
