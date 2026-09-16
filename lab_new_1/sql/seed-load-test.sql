-- ============================================================================
-- Нагрузочный датасет для БД сервиса ChakChakShop.
-- Только для локального/тестового окружения, в production не применять.
--
-- Запуск:
--   docker exec -i chakchakshop_postgres psql -U postgres -d chakchakshop -X -f - \
--     < seed-load-test.sql
-- ============================================================================

\echo '--- 1. 50 000 тестовых пользователей ---'
INSERT INTO users (id, username, email, password_hash, created_at)
SELECT gen_random_uuid(),
       'loadtest_user_' || g,
       'loadtest_' || g || '@example.com',
       '$2a$11$loadtestloadtestloadtestloadtestloadtestloadtestloadtes',
       NOW() - (random() * INTERVAL '2 years')
FROM generate_series(1, 50000) g
ON CONFLICT DO NOTHING;

-- Пронумерованный список тестовых клиентов: выбирать случайного через
-- OFFSET floor(random()*N) в LATERAL нельзя — подзапрос не коррелирован
-- с внешней строкой, PostgreSQL вычисляет его ОДИН раз, и все заказы
-- достаются одному пользователю. Номер клиента считаем построчно в CTE.
DROP TABLE IF EXISTS lt_users;
CREATE TEMP TABLE lt_users AS
SELECT id, row_number() OVER (ORDER BY id) AS rn
FROM users WHERE username LIKE 'loadtest_user_%';
CREATE INDEX ON lt_users(rn);
ANALYZE lt_users;

\echo '--- 2. 950 000 заказов, распределённых по 50 000 клиентов ---'
WITH gen AS (
    SELECT (floor(random() * 50000) + 1)::bigint AS rn,
           round((random() * 9000 + 450)::numeric, 2) AS amount,
           (ARRAY['Pending','Processing','Completed','Cancelled','Refunded'])[floor(random() * 5 + 1)::INT] AS status,
           NOW() - (random() * INTERVAL '2 years') AS created_at
    FROM generate_series(1, 950000)
)
INSERT INTO orders (id, user_id, total_amount, status, created_at, updated_at)
SELECT gen_random_uuid(), lu.id, gen.amount, gen.status, gen.created_at, NULL
FROM gen JOIN lt_users lu ON lu.rn = gen.rn;

\echo '--- 3. 50 000 заказов у крупного клиента customer@example.com ---'
INSERT INTO orders (id, user_id, total_amount, status, created_at, updated_at)
SELECT gen_random_uuid(),
       'aaaaaaaa-0000-0000-0000-000000000003'::uuid,
       round((random() * 9000 + 450)::numeric, 2),
       (ARRAY['Pending','Processing','Completed','Cancelled','Refunded'])[floor(random() * 5 + 1)::INT],
       NOW() - (random() * INTERVAL '2 years'),
       NULL
FROM generate_series(1, 50000);

\echo '--- 4. позиции заказов (2 на заказ) ---'
INSERT INTO order_items (id, order_id, product_id, quantity, unit_price, total_price)
SELECT gen_random_uuid(), o.id, p.id,
       (floor(random() * 3) + 1)::INT, p.price,
       p.price * ((floor(random() * 3) + 1)::INT)
FROM orders o
CROSS JOIN LATERAL (SELECT id, price FROM products ORDER BY random() LIMIT 2) p
WHERE NOT EXISTS (SELECT 1 FROM order_items oi WHERE oi.order_id = o.id);

VACUUM ANALYZE users;
VACUUM ANALYZE orders;
VACUUM ANALYZE order_items;

\echo '--- итог: распределение заказов по клиентам ---'
SELECT count(*) AS orders, count(DISTINCT user_id) AS distinct_customers FROM orders;
SELECT min(cnt) AS min_per_customer, round(avg(cnt), 1) AS avg_per_customer, max(cnt) AS max_per_customer
FROM (SELECT count(*) AS cnt FROM orders GROUP BY user_id) t;
