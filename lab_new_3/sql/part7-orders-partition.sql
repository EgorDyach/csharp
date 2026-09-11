-- =====================================================================
-- Часть 12, шаги 1-5: партиционирование рабочей таблицы orders
--                     RANGE по месяцам, ключ created_at
-- =====================================================================
--  Таблица : orders           — самая быстрорастущая таблица сервиса
--                               (5 000 003 строки, 1067 MB, 25 месяцев)
--  Ключ    : created_at       — есть в фильтрах аналитики и в ORDER BY
--  Страте- : RANGE по месяцу  — у заказов выраженный жизненный цикл:
--  гия                          свежие читают постоянно, старые — почти никогда
--
--  ВАЖНО: скрипт НЕ трогает работающую таблицу orders. Партиционированная
--  копия создаётся рядом под именем orders_partitioned, все замеры делаются
--  на ней. Переключение сервиса — отдельный скрипт part9-cutover.sql,
--  который выполняется осознанно и под присмотром.
-- =====================================================================
\timing on
\set ON_ERROR_STOP on
SET search_path = public;
SET TIME ZONE 'UTC';   -- границы партиций по timestamptz зависят от TimeZone

\echo '### 12.7 Каркас партиционированной таблицы'
CREATE TABLE public.orders_partitioned (
    id           uuid                     NOT NULL,
    user_id      uuid                     NOT NULL,
    total_amount numeric(18,2)            NOT NULL,
    status       character varying(50)    NOT NULL,
    created_at   timestamp with time zone NOT NULL,
    updated_at   timestamp with time zone
) PARTITION BY RANGE (created_at);

\echo '### 12.8 Помесячные партиции на весь период данных'
DO $$
DECLARE
    d date := date '2024-09-01';
BEGIN
    WHILE d < date '2026-10-01' LOOP
        EXECUTE format(
            'CREATE TABLE public.%I PARTITION OF public.orders_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            'orders_p_' || to_char(d, 'YYYY_MM'),
            d, d + INTERVAL '1 month');
        d := (d + INTERVAL '1 month')::date;
    END LOOP;
END $$;

-- Страховка: заказ с датой вне известных диапазонов не должен ронять INSERT
CREATE TABLE public.orders_p_default PARTITION OF public.orders_partitioned DEFAULT;

SELECT count(*) AS partitions_created
FROM pg_inherits WHERE inhparent = 'public.orders_partitioned'::regclass;

\echo '### 12.9 Перенос 5 000 003 строк'
INSERT INTO public.orders_partitioned (id, user_id, total_amount, status, created_at, updated_at)
SELECT id, user_id, total_amount, status, created_at, updated_at FROM public.orders;

\echo '### 12.10 Индексы создаём на родителе — в партициях появятся локальные'
-- Ограничение №1: первичный ключ партиционированной таблицы обязан содержать
-- ключ партиционирования, поэтому (id) превращается в (id, created_at).
ALTER TABLE public.orders_partitioned
    ADD CONSTRAINT "PK_orders_partitioned" PRIMARY KEY (id, created_at);
CREATE INDEX "IX_orders_p_created_at"         ON public.orders_partitioned (created_at DESC);
CREATE INDEX "IX_orders_p_user_id_created_at" ON public.orders_partitioned (user_id, created_at DESC);
CREATE INDEX "IX_orders_p_id"                 ON public.orders_partitioned (id);

ALTER TABLE public.orders_partitioned
    ADD CONSTRAINT "FK_orders_p_users_user_id"
    FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE RESTRICT;

ANALYZE public.orders_partitioned;

\echo '### 12.11 Распределение строк по партициям'
SELECT tableoid::regclass AS partition_name,
       count(*),
       pg_size_pretty(pg_total_relation_size(tableoid)) AS size
FROM public.orders_partitioned
GROUP BY tableoid ORDER BY 1;

\echo '### 12.12 Локальные индексы одной партиции'
SELECT indexrelid::regclass AS local_index,
       pg_size_pretty(pg_relation_size(indexrelid)) AS size
FROM pg_index WHERE indrelid = 'public.orders_p_2026_08'::regclass
ORDER BY 1;

\echo '### 12.13 Суммарный размер: партиционированная против обычной'
SELECT 'orders (обычная)'          AS table_name,
       pg_size_pretty(pg_total_relation_size('public.orders')) AS total
UNION ALL
SELECT 'orders_partitioned (25+1 партиция)',
       pg_size_pretty(sum(pg_total_relation_size(inhrelid)))
FROM pg_inherits WHERE inhparent = 'public.orders_partitioned'::regclass;
