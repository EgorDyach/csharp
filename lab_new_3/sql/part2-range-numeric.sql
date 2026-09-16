-- =====================================================================
-- Часть 3: RANGE PARTITIONING по числовому значению (цена товара)
-- =====================================================================
\timing on
\set ON_ERROR_STOP off
SET search_path = lab3, public;

-- ВАЖНО: квалифицируем схемой. Без префикса lab3 этот DROP находит
-- боевую public.products и сносит её вместе с внешними ключами.
DROP TABLE IF EXISTS lab3.products CASCADE;

\echo '### 3.1 Таблица, разделённая по ценовым сегментам'
CREATE TABLE lab3.products (
    id    BIGINT  NOT NULL,
    name  TEXT    NOT NULL,
    price NUMERIC NOT NULL
) PARTITION BY RANGE (price);

CREATE TABLE lab3.products_cheap     PARTITION OF lab3.products FOR VALUES FROM (0)    TO (100);
CREATE TABLE lab3.products_medium    PARTITION OF lab3.products FOR VALUES FROM (100)  TO (1000);
CREATE TABLE lab3.products_expensive PARTITION OF lab3.products FOR VALUES FROM (1000) TO (MAXVALUE);

\echo '### 3.2 Товары с разными ценами: куда они попали'
INSERT INTO lab3.products VALUES
    (1, 'Чак-чак мини 100 г',        99.99),
    (2, 'Чак-чак классический 500 г', 100.00),
    (3, 'Чак-чак подарочный 1 кг',    999.99),
    (4, 'Корпоративный набор',       1000.00),
    (5, 'Свадебный чак-чак 10 кг',   7500.00),
    (6, 'Пробник 50 г',                 0.00);

SELECT id, name, price, tableoid::regclass AS landed_in
FROM lab3.products ORDER BY id;

\echo '### 3.3 Нагрузочные данные: 300 000 товаров'
INSERT INTO lab3.products (id, name, price)
SELECT g,
       'product-' || g,
       round((random() * 5000)::numeric, 2)
FROM generate_series(100, 300000) g;
ANALYZE lab3.products;

SELECT tableoid::regclass AS partition_name, COUNT(*), min(price), max(price)
FROM lab3.products GROUP BY tableoid ORDER BY partition_name;

\echo '### 3.4 Задание: SELECT * FROM lab3.products WHERE price >= 100 AND price < 500'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE price >= 100 AND price < 500;

\echo '### 3.5 Контрольный опыт: диапазон, пересекающий границу партиций'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE price >= 90 AND price < 500;

\echo '### 3.6 Контрольный опыт: запрос без ключа партиционирования'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE name = 'product-12345';
