-- =====================================================================
-- Часть 4-5: LIST PARTITIONING и DEFAULT-партиция
-- =====================================================================
\timing on
\set ON_ERROR_STOP off
SET search_path = lab3, public;

DROP TABLE IF EXISTS lab3.customers CASCADE;

\echo '### 4.1 Разделение по категориям'
CREATE TABLE lab3.customers (
    id            BIGINT      NOT NULL,
    name          TEXT        NOT NULL,
    customer_type VARCHAR(30) NOT NULL
) PARTITION BY LIST (customer_type);

CREATE TABLE lab3.customers_b2c        PARTITION OF lab3.customers FOR VALUES IN ('B2C');
CREATE TABLE lab3.customers_b2b        PARTITION OF lab3.customers FOR VALUES IN ('B2B');
CREATE TABLE lab3.customers_enterprise PARTITION OF lab3.customers FOR VALUES IN ('Enterprise');

\echo '### 4.2 Данные: реалистичный перекос 1 000 000 / 150 000 / 20 000'
INSERT INTO lab3.customers
SELECT g, 'b2c-client-' || g, 'B2C'        FROM generate_series(1, 1000000) g;
INSERT INTO lab3.customers
SELECT 1000000 + g, 'b2b-client-' || g, 'B2B' FROM generate_series(1, 150000) g;
INSERT INTO lab3.customers
SELECT 2000000 + g, 'ent-client-' || g, 'Enterprise' FROM generate_series(1, 20000) g;
ANALYZE lab3.customers;

SELECT tableoid::regclass AS partition_name, COUNT(*)
FROM lab3.customers GROUP BY tableoid ORDER BY partition_name;

\echo '### 4.3 Задание: SELECT * FROM customers WHERE customer_type = ''B2B'''
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.customers WHERE customer_type = 'B2B';

\echo '### 4.4 Несколько категорий сразу: IN (...) тоже отсекает'
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_type, count(*) FROM lab3.customers
WHERE customer_type IN ('B2B','Enterprise') GROUP BY customer_type;

-- =====================================================================
-- Часть 5. LIST PARTITIONING: что делать с неизвестным значением
-- =====================================================================
\echo '### 5.1 Вставка значения, для которого партиции нет'
INSERT INTO lab3.customers VALUES (100, 'Test User', 'VIP');

\echo '### 5.2 Создаём DEFAULT-партицию и повторяем вставку'
CREATE TABLE lab3.customers_default PARTITION OF lab3.customers DEFAULT;
INSERT INTO lab3.customers VALUES (100, 'Test User', 'VIP');

SELECT id, name, customer_type, tableoid::regclass AS landed_in
FROM lab3.customers WHERE customer_type = 'VIP';

\echo '### 5.3 Цена DEFAULT №1: запрос по значению из DEFAULT читает DEFAULT'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.customers WHERE customer_type = 'VIP';

\echo '### 5.4 Проверка: запрос по явно перечисленному типу DEFAULT не трогает'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab3.customers WHERE customer_type = 'B2B';

\echo '### 5.5 Цена DEFAULT №2: наполним DEFAULT — так бывает, если о новом типе не знали'
INSERT INTO lab3.customers
SELECT 3000000 + g, 'vip-client-' || g, 'VIP' FROM generate_series(1, 500000) g;
ANALYZE lab3.customers;

SELECT tableoid::regclass AS partition_name, COUNT(*)
FROM lab3.customers GROUP BY tableoid ORDER BY partition_name;

\echo '### 5.6 Попытка «узаконить» тип VIP отдельной партицией'
--      PostgreSQL обязан убедиться, что в DEFAULT не осталось VIP-строк
CREATE TABLE lab3.customers_vip PARTITION OF lab3.customers FOR VALUES IN ('VIP');

\echo '### 5.7 Правильная процедура: вынести строки из DEFAULT и присоединить партицию'
BEGIN;
ALTER TABLE lab3.customers DETACH PARTITION lab3.customers_default;
CREATE TABLE lab3.customers_vip (LIKE lab3.customers INCLUDING DEFAULTS);
INSERT INTO lab3.customers_vip SELECT * FROM lab3.customers_default WHERE customer_type = 'VIP';
DELETE FROM lab3.customers_default WHERE customer_type = 'VIP';
ALTER TABLE lab3.customers ATTACH PARTITION lab3.customers_vip FOR VALUES IN ('VIP');
ALTER TABLE lab3.customers ATTACH PARTITION lab3.customers_default DEFAULT;
COMMIT;
ANALYZE lab3.customers;

SELECT tableoid::regclass AS partition_name, COUNT(*)
FROM lab3.customers GROUP BY tableoid ORDER BY partition_name;

\echo '### 5.8 После переноса запрос по VIP снова читает одну партицию'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab3.customers WHERE customer_type = 'VIP';
