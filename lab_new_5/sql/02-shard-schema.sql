-- =====================================================================
-- Схема одного шарда
-- =====================================================================
-- Выполняется одинаково на каждом узле. Шард не знает ни своего номера,
-- ни о существовании соседей — номер знает только роутер в сервисе.
--
-- Что лежит на шарде:
--   orders       — шардируется по user_id;
--   order_items  — едет ВМЕСТЕ с заказом. Ради этого в таблицу добавлен
--                  user_id, которого нет в исходной схеме: без него
--                  позицию заказа некуда маршрутизировать, и JOIN
--                  orders x order_items стал бы межшардовым;
--   users,
--   products,
--   categories   — справочники. Они маленькие и нужны всем шардам,
--                  поэтому копируются на каждый целиком. Это стандартный
--                  приём: reference tables реплицируются, чтобы JOIN
--                  к ним оставался локальным.
-- =====================================================================

CREATE TABLE IF NOT EXISTS users (
    id            uuid PRIMARY KEY,
    username      varchar(100) NOT NULL,
    email         varchar(255) NOT NULL,
    password_hash varchar(255) NOT NULL,
    created_at    timestamptz  NOT NULL,
    updated_at    timestamptz
);

CREATE TABLE IF NOT EXISTS categories (
    id          uuid PRIMARY KEY,
    name        varchar(200) NOT NULL,
    description text         NOT NULL,
    created_at  timestamptz  NOT NULL,
    updated_at  timestamptz
);

CREATE TABLE IF NOT EXISTS products (
    id             uuid PRIMARY KEY,
    name           varchar(200)  NOT NULL,
    description    text          NOT NULL,
    price          numeric(18,2) NOT NULL,
    stock_quantity integer       NOT NULL,
    category_id    uuid          NOT NULL,
    created_at     timestamptz   NOT NULL,
    updated_at     timestamptz
);

CREATE TABLE IF NOT EXISTS orders (
    id           uuid PRIMARY KEY,
    user_id      uuid          NOT NULL,
    total_amount numeric(18,2) NOT NULL,
    status       varchar(50)   NOT NULL,
    created_at   timestamptz   NOT NULL,
    updated_at   timestamptz
);

CREATE TABLE IF NOT EXISTS order_items (
    id          uuid PRIMARY KEY,
    order_id    uuid          NOT NULL,
    user_id     uuid          NOT NULL,   -- денормализация ради co-location
    product_id  uuid          NOT NULL,
    quantity    integer       NOT NULL,
    unit_price  numeric(18,2) NOT NULL,
    total_price numeric(18,2) NOT NULL
);

-- Индексы под запросы сервиса: главный — «заказы пользователя за период».
CREATE INDEX IF NOT EXISTS ix_orders_user_created ON orders (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS ix_orders_created      ON orders (created_at DESC);
CREATE INDEX IF NOT EXISTS ix_items_order         ON order_items (order_id);
CREATE INDEX IF NOT EXISTS ix_items_user          ON order_items (user_id);

-- Служебная табличка: кто этот шард и по какой стратегии он набит.
CREATE TABLE IF NOT EXISTS shard_info (
    shard_id     int PRIMARY KEY,
    shard_count  int         NOT NULL,
    strategy     text        NOT NULL,
    loaded_at    timestamptz NOT NULL DEFAULT now()
);
