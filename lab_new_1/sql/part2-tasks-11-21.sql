-- ============================================================================
-- Лабораторная работа №1. Индексы и EXPLAIN ANALYZE в PostgreSQL
-- Часть 2. Задания 11-21 (продолжение работы с тестовой базой)
--
-- Скрипт продолжает состояние, оставленное part1-tasks-01-10.sql:
-- таблица orders на 1 000 000 строк и три индекса
-- (idx_orders_user_id, idx_orders_status, idx_orders_created_at).
--
-- Запуск:
--   docker exec -i chakchakshop_postgres psql -U postgres -d lab_indexes -X -f - \
--     < part2-tasks-11-21.sql
-- ============================================================================

\echo ''
\echo '================================================================'
\echo ' ИСХОДНОЕ СОСТОЯНИЕ (после заданий 1-10)'
\echo '================================================================'
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes WHERE relname = 'orders' ORDER BY 1;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 11. Несколько условий и несколько индексов'
\echo '================================================================'
\echo '--- 11.1 запрос из задания: user_id = 123 AND status = PAID ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';

\echo '--- 11.2 подобранный запрос, в котором появляется BitmapAnd ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders
WHERE user_id BETWEEN 1000 AND 2000
  AND created_at > NOW() - INTERVAL '1 month';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 12. Составной индекс (user_id, status)'
\echo '================================================================'
CREATE INDEX idx_orders_user_status ON orders(user_id, status);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_user_status')) AS composite_size;

\echo '--- 12.1 ДО: составной индекс временно скрыт (работают два отдельных) ---'
BEGIN;
DROP INDEX idx_orders_user_status;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';
ROLLBACK;

\echo '--- прогрев ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';
\echo '--- 12.2 ПОСЛЕ: доступен составной индекс ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND status = 'PAID';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 13. Порядок колонок в составном индексе'
\echo '================================================================'
CREATE INDEX idx_orders_user_created_at ON orders(user_id, created_at);
ANALYZE orders;

\echo '--- 13.A изоляция: доступен ТОЛЬКО (user_id, created_at) ---'
\echo '--- Запрос 1: WHERE user_id = 123 ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at, idx_orders_user_status;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 123;
ROLLBACK;

\echo '--- Запрос 2: WHERE user_id = 123 AND created_at > NOW() - 30 days ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at, idx_orders_user_status;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND created_at > NOW() - INTERVAL '30 days';
ROLLBACK;

\echo '--- Запрос 3: WHERE created_at > NOW() - 30 days (без user_id!) ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at, idx_orders_user_status;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';
ROLLBACK;

CREATE INDEX idx_orders_created_at_user ON orders(created_at, user_id);
ANALYZE orders;

\echo '--- 13.B изоляция: доступен ТОЛЬКО (created_at, user_id) ---'
\echo '--- Запрос 1: WHERE user_id = 123 ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at,
            idx_orders_user_status, idx_orders_user_created_at;
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM orders WHERE user_id = 123;
ROLLBACK;

\echo '--- Запрос 2: WHERE user_id = 123 AND created_at > NOW() - 30 days ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at,
            idx_orders_user_status, idx_orders_user_created_at;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 123 AND created_at > NOW() - INTERVAL '30 days';
ROLLBACK;

\echo '--- Запрос 3: WHERE created_at > NOW() - 30 days ---'
BEGIN;
DROP INDEX idx_orders_user_id, idx_orders_status, idx_orders_created_at,
            idx_orders_user_status, idx_orders_user_created_at;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE created_at > NOW() - INTERVAL '30 days';
ROLLBACK;

\echo '--- 13.C размеры обоих индексов ---'
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_orders_user_created_at','idx_orders_created_at_user');

\echo ''
\echo '================================================================'
\echo ' ПОДГОТОВКА К ЗАДАНИЯМ 14-15: "горячий" пользователь'
\echo '================================================================'
\echo 'В сгенерированных данных на каждого пользователя приходится ~10 заказов.'
\echo 'На выборке в 10 строк разницы между планами не видно: сортировать нечего.'
\echo 'Добавляем крупного клиента (user_id = 1) с 50 000 заказов - это реальный'
\echo 'сценарий, ради которого и нужен индекс под WHERE + ORDER BY + LIMIT.'

-- created_at привязан к диапазону уже существующих данных, а не к NOW():
-- иначе заказы этого пользователя оказались бы самыми свежими в таблице
-- и исказили бы запросы вида "последние N заказов".
INSERT INTO orders (user_id, product_id, status, amount, created_at, updated_at)
SELECT 1,
       (random() * 10000)::BIGINT,
       (ARRAY['NEW','PAID','DELIVERED','CANCELLED'])[floor(random() * 4 + 1)::INT],
       random() * 10000,
       (SELECT max(created_at) FROM orders) - (random() * INTERVAL '2 years'),
       NOW()
FROM generate_series(1, 50000);

VACUUM ANALYZE orders;
SELECT count(*) AS total_rows FROM orders;
SELECT count(*) AS hot_user_rows FROM orders WHERE user_id = 1;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 14. WHERE + ORDER BY'
\echo '================================================================'
\echo '--- 14.1 ДО: составные индексы скрыты -> ожидаем Sort ---'
BEGIN;
DROP INDEX idx_orders_user_created_at, idx_orders_created_at_user, idx_orders_user_status;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC;
ROLLBACK;

CREATE INDEX idx_orders_user_created_at_desc ON orders(user_id, created_at DESC);
ANALYZE orders;

\echo '--- 14.2 ПОСЛЕ: доступен индекс (user_id, created_at DESC) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC;

\echo '--- 14.3 проверка гипотезы: почему Sort не исчез. Форсируем Index Scan ---'
SET enable_bitmapscan = off;
SET enable_sort = off;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC;
RESET ALL;

\echo '--- 14.4 тот же запрос, но с LIMIT 100 ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC LIMIT 100;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 15. Pagination Query: GET /users/1/orders?limit=20'
\echo '================================================================'
\echo '--- 15.1 ДО: только одноколоночные индексы ---'
BEGIN;
DROP INDEX idx_orders_user_created_at, idx_orders_created_at_user,
            idx_orders_user_status, idx_orders_user_created_at_desc;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC LIMIT 20;
ROLLBACK;

\echo '--- прогрев ---'
EXPLAIN ANALYZE SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC LIMIT 20;
\echo '--- 15.2 ПОСЛЕ: подобранный индекс (user_id, created_at DESC) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE user_id = 1 ORDER BY created_at DESC LIMIT 20;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 16. Index Only Scan'
\echo '================================================================'
\echo '--- 16.1 SELECT id, user_id: покрывающего индекса пока нет ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 1;

CREATE INDEX idx_orders_user_id_id ON orders(user_id, id);
VACUUM ANALYZE orders;

\echo '--- 16.2 ПОСЛЕ создания (user_id, id) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id FROM orders WHERE user_id = 1;

\echo '--- 16.3 добавили колонку, которой нет в индексе -> Index Only Scan исчезает ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, amount FROM orders WHERE user_id = 1;

\echo '--- 16.4 дополнительное задание: INCLUDE ---'
CREATE INDEX idx_orders_user_id_include
    ON orders(user_id) INCLUDE (id, status, created_at);
VACUUM ANALYZE orders;
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname IN ('idx_orders_user_id_id','idx_orders_user_id_include');

EXPLAIN (ANALYZE, BUFFERS)
SELECT id, status, created_at FROM orders WHERE user_id = 1;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 17. Partial Index'
\echo '================================================================'
\echo '--- 17.1 ДО: WHERE status = NEW ORDER BY created_at LIMIT 100 ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at LIMIT 100;

CREATE INDEX idx_orders_new ON orders(created_at) WHERE status = 'NEW';
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_new'))        AS partial_size,
       pg_size_pretty(pg_relation_size('idx_orders_created_at')) AS full_index_size;

\echo '--- 17.2 ПОСЛЕ partial index (status = NEW занимает 25% таблицы) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'NEW' ORDER BY created_at LIMIT 100;

\echo '--- 17.3 сценарий, ради которого partial index и придуман: редкий статус ---'
\echo 'Задание предполагает, что NEW встречается редко, но генератор раздал'
\echo 'все четыре статуса поровну. Делаем действительно редкий статус (0.5%).'
UPDATE orders SET status = 'REFUND_PENDING' WHERE id % 200 = 0;
VACUUM ANALYZE orders;
SELECT status, count(*), round(100.0*count(*)/sum(count(*)) OVER (), 3) AS pct
FROM orders GROUP BY status ORDER BY 2 DESC;

\echo '--- 17.4 ДО partial index по редкому статусу ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'REFUND_PENDING' ORDER BY created_at LIMIT 100;

CREATE INDEX idx_orders_refund_pending
    ON orders(created_at) WHERE status = 'REFUND_PENDING';
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_refund_pending')) AS partial_size,
       pg_size_pretty(pg_relation_size('idx_orders_status'))         AS full_status_index;

\echo '--- 17.5 ПОСЛЕ partial index по редкому статусу ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'REFUND_PENDING' ORDER BY created_at LIMIT 100;

\echo '--- 17.6 тот же partial index неприменим к другому статусу ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE status = 'PAID' ORDER BY created_at LIMIT 100;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 18. Expression Index'
\echo '================================================================'
DROP TABLE IF EXISTS users;
CREATE TABLE users (
    id BIGSERIAL PRIMARY KEY,
    email VARCHAR(255) NOT NULL
);
INSERT INTO users (email)
SELECT 'User' || g || '@Example.com' FROM generate_series(1, 500000) g;
INSERT INTO users (email) VALUES ('Test@Example.COM');

CREATE INDEX idx_users_email ON users(email);
ANALYZE users;
SELECT count(*) AS users_rows FROM users;

\echo '--- 18.1 обычный индекс по email + LOWER() в запросе ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';

\echo '--- 18.2 тот же индекс без функции - работает ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE email = 'Test@Example.COM';

CREATE INDEX idx_users_lower_email ON users(LOWER(email));
ANALYZE users;
SELECT pg_size_pretty(pg_relation_size('idx_users_lower_email')) AS expression_index_size;

\echo '--- 18.3 ПОСЛЕ создания индекса по выражению ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM users WHERE LOWER(email) = 'test@example.com';

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 19. Цена индексов: влияние на INSERT и UPDATE'
\echo '================================================================'
DROP TABLE IF EXISTS bench_no_idx;
DROP TABLE IF EXISTS bench_with_idx;
CREATE TABLE bench_no_idx   (LIKE orders INCLUDING DEFAULTS);
CREATE TABLE bench_with_idx (LIKE orders INCLUDING DEFAULTS);

CREATE INDEX b_idx_user      ON bench_with_idx(user_id);
CREATE INDEX b_idx_status    ON bench_with_idx(status);
CREATE INDEX b_idx_created   ON bench_with_idx(created_at);
CREATE INDEX b_idx_user_stat ON bench_with_idx(user_id, status);
CREATE INDEX b_idx_user_crea ON bench_with_idx(user_id, created_at DESC);

\echo '--- 19.1 INSERT 200 000 строк в таблицу БЕЗ индексов ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
INSERT INTO bench_no_idx (user_id, product_id, status, amount, created_at, updated_at)
SELECT (random()*100000)::BIGINT, (random()*10000)::BIGINT,
       (ARRAY['NEW','PAID','DELIVERED','CANCELLED'])[floor(random()*4+1)::INT],
       random()*10000, NOW() - (random() * INTERVAL '2 years'), NOW()
FROM generate_series(1, 200000);

\echo '--- 19.2 INSERT 200 000 строк в таблицу С 5 индексами ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
INSERT INTO bench_with_idx (user_id, product_id, status, amount, created_at, updated_at)
SELECT (random()*100000)::BIGINT, (random()*10000)::BIGINT,
       (ARRAY['NEW','PAID','DELIVERED','CANCELLED'])[floor(random()*4+1)::INT],
       random()*10000, NOW() - (random() * INTERVAL '2 years'), NOW()
FROM generate_series(1, 200000);

\echo '--- 19.3 UPDATE 50 000 строк: без индексов ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
UPDATE bench_no_idx SET status = 'PAID' WHERE id % 4 = 0;

\echo '--- 19.4 UPDATE 50 000 строк: с индексами ---'
EXPLAIN (ANALYZE, TIMING OFF, COSTS OFF)
UPDATE bench_with_idx SET status = 'PAID' WHERE id % 4 = 0;

\echo '--- 19.5 сколько места занимают данные и сколько индексы ---'
SELECT relname,
       pg_size_pretty(pg_relation_size(oid))       AS heap,
       pg_size_pretty(pg_indexes_size(oid))        AS indexes,
       pg_size_pretty(pg_total_relation_size(oid)) AS total
FROM pg_class
WHERE relname IN ('bench_no_idx','bench_with_idx','orders')
ORDER BY relname;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 20. Анализ существующих индексов'
\echo '================================================================'
SELECT s.relname,
       s.indexrelname,
       s.idx_scan,
       s.idx_tup_read,
       s.idx_tup_fetch,
       pg_size_pretty(pg_relation_size(s.indexrelid)) AS size,
       i.indisunique AS is_unique
FROM pg_stat_user_indexes s
JOIN pg_index i ON i.indexrelid = s.indexrelid
WHERE s.relname IN ('orders','users')
ORDER BY s.idx_scan, s.relname;

\echo ''
\echo '================================================================'
\echo ' ЗАДАНИЕ 21. Финальная оптимизация запроса'
\echo '================================================================'
\echo '  SELECT id, amount, status, created_at FROM orders'
\echo '  WHERE user_id = $1 AND status = ''PAID'''
\echo '    AND created_at >= NOW() - INTERVAL ''30 days'''
\echo '  ORDER BY created_at DESC LIMIT 50;'

SELECT count(*) AS matching_rows
FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days';

\echo '--- 21.1 ДО: базовый набор одноколоночных индексов ---'
BEGIN;
DROP INDEX idx_orders_user_status, idx_orders_user_created_at, idx_orders_created_at_user,
            idx_orders_user_created_at_desc, idx_orders_user_id_id, idx_orders_user_id_include;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;
ROLLBACK;

\echo '--- 21.2 промежуточный вариант: индекс (user_id, created_at DESC) ---'
BEGIN;
DROP INDEX idx_orders_user_status, idx_orders_user_created_at, idx_orders_created_at_user,
            idx_orders_user_id_id, idx_orders_user_id_include;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;
ROLLBACK;

CREATE INDEX idx_orders_user_status_created ON orders(user_id, status, created_at DESC);
ANALYZE orders;
SELECT pg_size_pretty(pg_relation_size('idx_orders_user_status_created')) AS target_index_size;

\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;

\echo '--- 21.3 ПОСЛЕ: целевой индекс (user_id, status, created_at DESC) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;

\echo '--- 21.4 проверка гипотезы: окупится ли covering-индекс с INCLUDE (amount)? ---'
CREATE INDEX idx_orders_user_status_created_incl
    ON orders(user_id, status, created_at DESC) INCLUDE (amount);
VACUUM ANALYZE orders;
SELECT indexrelname, pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_stat_user_indexes
WHERE indexrelname LIKE 'idx_orders_user_status_created%';

\echo 'Какой из двух индексов выберет планировщик:'
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;

\echo 'Принудительно через covering-индекс (обычный скрыт):'
BEGIN;
DROP INDEX idx_orders_user_status_created;
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, amount, status, created_at FROM orders
WHERE user_id = 1 AND status = 'PAID' AND created_at >= NOW() - INTERVAL '30 days'
ORDER BY created_at DESC LIMIT 50;
ROLLBACK;

\echo 'Covering-индекс не выигрывает - удаляем его, чтобы не платить за запись:'
DROP INDEX idx_orders_user_status_created_incl;

\echo ''
\echo '================================================================'
\echo ' ИТОГ ЧАСТИ 2'
\echo '================================================================'
SELECT indexrelname AS index_name,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size,
       idx_scan AS times_used
FROM pg_stat_user_indexes
WHERE relname = 'orders'
ORDER BY pg_relation_size(indexrelid) DESC;

SELECT pg_size_pretty(pg_relation_size('orders')) AS heap,
       pg_size_pretty(pg_indexes_size('orders'))  AS all_indexes;
