-- =====================================================================
-- Части 4, 5, 7: распределение данных и цена расширения кластера
-- =====================================================================
-- Шардируемая сущность — orders, ключ шардирования — user_id.
-- Номер шарда у заказа определяется НЕ его собственным id, а владельцем:
-- все заказы одного клиента обязаны лежать вместе, иначе главный запрос
-- сервиса «заказы этого пользователя» превратится в опрос всех узлов.
--
-- Считаем по пользователям, а не по заказам: пользователей 50 003,
-- заказов 5 000 003, а раскладка у них одна и та же. Для количества
-- записей на шарде счётчики заказов просто суммируются.
-- =====================================================================
\timing on
\set ON_ERROR_STOP on

SELECT shardlab.build_ring(3) AS ring_3_points,
       shardlab.build_ring(4) AS ring_4_points;

DROP TABLE IF EXISTS shardlab.user_assignment;

CREATE TABLE shardlab.user_assignment AS
SELECT u.id                                          AS user_id,
       shardlab.shard_hash(u.id::text)               AS key_hash,
       shardlab.shard_by_modulo(u.id::text, 3)       AS mod_3,
       shardlab.shard_by_modulo(u.id::text, 4)       AS mod_4,
       shardlab.shard_by_ring(u.id::text, 3)         AS ring_3,
       shardlab.shard_by_ring(u.id::text, 4)         AS ring_4,
       coalesce(o.orders_count, 0)                   AS orders_count
FROM users u
LEFT JOIN (
    SELECT user_id, count(*) AS orders_count FROM orders GROUP BY user_id
) o ON o.user_id = u.id;

ALTER TABLE shardlab.user_assignment ADD PRIMARY KEY (user_id);
ANALYZE shardlab.user_assignment;

\echo '### 4.1 Сколько всего объектов распределяем'
SELECT count(*)              AS users,
       sum(orders_count)     AS orders,
       max(orders_count)     AS max_orders_per_user,
       round(avg(orders_count), 2) AS avg_orders_per_user
FROM shardlab.user_assignment;

\echo '### 4.2 Распределение по 3 шардам: hash(user_id) % 3'
SELECT mod_3 AS shard,
       count(*)                                                        AS users,
       sum(orders_count)                                               AS orders,
       round(100.0 * count(*)          / sum(count(*))      OVER (), 3) AS users_pct,
       round(100.0 * sum(orders_count) / sum(sum(orders_count)) OVER (), 3) AS orders_pct
FROM shardlab.user_assignment
GROUP BY mod_3 ORDER BY mod_3;

\echo '### 4.3 Распределение по 3 шардам: consistent hashing (256 vnode на шард)'
SELECT ring_3 AS shard,
       count(*)                                                        AS users,
       sum(orders_count)                                               AS orders,
       round(100.0 * count(*)          / sum(count(*))      OVER (), 3) AS users_pct,
       round(100.0 * sum(orders_count) / sum(sum(orders_count)) OVER (), 3) AS orders_pct
FROM shardlab.user_assignment
GROUP BY ring_3 ORDER BY ring_3;

\echo '### 4.4 Перекос: отклонение самого большого шарда от идеальной трети'
SELECT 'hash % 3' AS strategy,
       max(orders) AS max_shard_orders, min(orders) AS min_shard_orders,
       round(100.0 * (max(orders) - min(orders)) / avg(orders), 2) AS spread_pct
FROM (SELECT mod_3 AS s, sum(orders_count) AS orders FROM shardlab.user_assignment GROUP BY 1) t
UNION ALL
SELECT 'consistent hashing',
       max(orders), min(orders),
       round(100.0 * (max(orders) - min(orders)) / avg(orders), 2)
FROM (SELECT ring_3 AS s, sum(orders_count) AS orders FROM shardlab.user_assignment GROUP BY 1) t;

-- =====================================================================
\echo '### 5.1 Задание 5: что будет при переходе 3 -> 4 шарда по модулю'
-- =====================================================================
SELECT count(*) FILTER (WHERE mod_3 <> mod_4)                       AS users_moved,
       count(*) FILTER (WHERE mod_3 =  mod_4)                       AS users_stayed,
       sum(orders_count) FILTER (WHERE mod_3 <> mod_4)              AS orders_moved,
       sum(orders_count) FILTER (WHERE mod_3 =  mod_4)              AS orders_stayed,
       round(100.0 * sum(orders_count) FILTER (WHERE mod_3 <> mod_4)
             / sum(orders_count), 2)                                AS orders_moved_pct
FROM shardlab.user_assignment;

\echo '### 5.2 Куда именно поехали данные при hash % N'
SELECT mod_3 AS from_shard, mod_4 AS to_shard, sum(orders_count) AS orders
FROM shardlab.user_assignment
GROUP BY mod_3, mod_4 ORDER BY mod_3, mod_4;

-- =====================================================================
\echo '### 7.1 Задание 7: тот же переход, но по кольцу'
-- =====================================================================
SELECT count(*) FILTER (WHERE ring_3 <> ring_4)                     AS users_moved,
       count(*) FILTER (WHERE ring_3 =  ring_4)                     AS users_stayed,
       sum(orders_count) FILTER (WHERE ring_3 <> ring_4)            AS orders_moved,
       sum(orders_count) FILTER (WHERE ring_3 =  ring_4)            AS orders_stayed,
       round(100.0 * sum(orders_count) FILTER (WHERE ring_3 <> ring_4)
             / sum(orders_count), 2)                                AS orders_moved_pct
FROM shardlab.user_assignment;

\echo '### 7.2 Куда поехали данные при consistent hashing'
SELECT ring_3 AS from_shard, ring_4 AS to_shard, sum(orders_count) AS orders
FROM shardlab.user_assignment
GROUP BY ring_3, ring_4 ORDER BY ring_3, ring_4;

\echo '### 7.3 Итоговое сравнение стратегий'
SELECT 'hash(key) % N'      AS strategy,
       round(100.0 * sum(orders_count) FILTER (WHERE mod_3 <> mod_4) / sum(orders_count), 2)  AS moved_pct,
       sum(orders_count) FILTER (WHERE mod_3 <> mod_4)                                        AS moved_orders
FROM shardlab.user_assignment
UNION ALL
SELECT 'Consistent Hashing',
       round(100.0 * sum(orders_count) FILTER (WHERE ring_3 <> ring_4) / sum(orders_count), 2),
       sum(orders_count) FILTER (WHERE ring_3 <> ring_4)
FROM shardlab.user_assignment;

-- =====================================================================
\echo '### 8.1 Два среза одного и того же: ключи против объёма'
-- =====================================================================
-- Хеш распределяет КЛЮЧИ. Объём данных он распределяет только в той мере,
-- в какой объём равномерно размазан по ключам. В этом наборе он не размазан:
-- два аккаунта нагрузочного генератора из лабораторной №2 держат по
-- 1 900 тыс. заказов каждый при медиане 19 заказов на пользователя.
SELECT 'hash % N'           AS strategy,
       round(100.0 * count(*) FILTER (WHERE mod_3 <> mod_4) / count(*), 2)                       AS keys_moved_pct,
       round(100.0 * sum(orders_count) FILTER (WHERE mod_3 <> mod_4) / sum(orders_count), 2)     AS volume_moved_pct
FROM shardlab.user_assignment
UNION ALL
SELECT 'Consistent Hashing',
       round(100.0 * count(*) FILTER (WHERE ring_3 <> ring_4) / count(*), 2),
       round(100.0 * sum(orders_count) FILTER (WHERE ring_3 <> ring_4) / sum(orders_count), 2)
FROM shardlab.user_assignment;

\echo '### 8.2 Кто перекашивает картину'
SELECT u.username, a.orders_count, a.mod_3, a.ring_3
FROM shardlab.user_assignment a JOIN users u ON u.id = a.user_id
ORDER BY a.orders_count DESC LIMIT 4;

SELECT round(avg(orders_count), 2) AS avg_orders,
       percentile_cont(0.5) WITHIN GROUP (ORDER BY orders_count) AS median_orders,
       percentile_cont(0.99) WITHIN GROUP (ORDER BY orders_count) AS p99_orders,
       max(orders_count) AS max_orders
FROM shardlab.user_assignment;

\echo '### 8.3 Распределение без двух аномальных аккаунтов'
--      Так видно, что сама хеш-функция раскладывает данные ровно.
WITH normal AS (
    SELECT * FROM shardlab.user_assignment WHERE orders_count < 100000
)
SELECT mod_3 AS shard, count(*) AS users, sum(orders_count) AS orders,
       round(100.0 * sum(orders_count) / sum(sum(orders_count)) OVER (), 2) AS orders_pct
FROM normal GROUP BY mod_3 ORDER BY mod_3;

WITH normal AS (
    SELECT * FROM shardlab.user_assignment WHERE orders_count < 100000
)
SELECT ring_3 AS shard, count(*) AS users, sum(orders_count) AS orders,
       round(100.0 * sum(orders_count) / sum(sum(orders_count)) OVER (), 2) AS orders_pct
FROM normal GROUP BY ring_3 ORDER BY ring_3;

\echo '### 8.4 Переезд без аномалий: чистая цена смены N'
WITH normal AS (
    SELECT * FROM shardlab.user_assignment WHERE orders_count < 100000
)
SELECT 'hash % N'           AS strategy,
       round(100.0 * sum(orders_count) FILTER (WHERE mod_3 <> mod_4) / sum(orders_count), 2)  AS volume_moved_pct
FROM normal
UNION ALL
SELECT 'Consistent Hashing',
       round(100.0 * sum(orders_count) FILTER (WHERE ring_3 <> ring_4) / sum(orders_count), 2)
FROM normal;
