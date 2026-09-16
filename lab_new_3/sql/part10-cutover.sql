-- =====================================================================
-- Часть 12, шаг 7: переключение сервиса на партиционированную таблицу
-- =====================================================================
-- ВНИМАНИЕ. Этот скрипт меняет схему работающего сервиса и в рамках
-- лабораторной НЕ выполнялся: все замеры сделаны на копии
-- orders_partitioned, созданной скриптом part7. Скрипт приложен потому,
-- что без него часть «шаг 7» остаётся словами: переключение — это
-- ровно одна транзакция, и её текст должен быть виден целиком.
--
-- Перед запуском:
--   1) остановить запись в orders (окно обслуживания либо read-only режим);
--   2) догнать orders_partitioned строками, добавленными после копирования;
--   3) проверить, что счётчики совпадают:
--        SELECT (SELECT count(*) FROM orders) = (SELECT count(*) FROM orders_partitioned);
--   4) снять бэкап.
--
-- Откат: обратное переименование, текст внизу файла.
-- =====================================================================
\set ON_ERROR_STOP on
SET search_path = public;
SET TIME ZONE 'UTC';

BEGIN;

-- Блокируем обе таблицы сразу, чтобы между переименованиями никто
-- не увидел базу в промежуточном состоянии.
LOCK TABLE public.orders, public.orders_partitioned IN ACCESS EXCLUSIVE MODE;

-- Ограничение партиционирования: внешний ключ order_items -> orders(id)
-- сохранить нельзя. Уникальный индекс партиционированной таблицы обязан
-- содержать ключ партиционирования, то есть (id, created_at);
-- ссылаться на один только id больше не на что.
ALTER TABLE public.order_items DROP CONSTRAINT "FK_order_items_orders_order_id";

ALTER TABLE public.orders RENAME TO orders_unpartitioned;
ALTER INDEX public."PK_orders"                    RENAME TO "PK_orders_unpartitioned";
ALTER INDEX public."IX_orders_created_at"         RENAME TO "IX_orders_unpart_created_at";
ALTER INDEX public."IX_orders_user_id"            RENAME TO "IX_orders_unpart_user_id";
ALTER INDEX public."IX_orders_user_id_created_at" RENAME TO "IX_orders_unpart_user_id_created_at";

ALTER TABLE public.orders_partitioned RENAME TO orders;
ALTER INDEX public."PK_orders_partitioned"        RENAME TO "PK_orders";
ALTER INDEX public."IX_orders_p_created_at"       RENAME TO "IX_orders_created_at";
ALTER INDEX public."IX_orders_p_user_id_created_at" RENAME TO "IX_orders_user_id_created_at";
ALTER INDEX public."IX_orders_p_id"               RENAME TO "IX_orders_id";

-- Компенсация за потерянный ON DELETE CASCADE: позиции заказа удаляет триггер.
CREATE OR REPLACE FUNCTION public.orders_cascade_delete_items() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    DELETE FROM public.order_items WHERE order_id = OLD.id;
    RETURN OLD;
END $$;

CREATE TRIGGER trg_orders_cascade_delete_items
    BEFORE DELETE ON public.orders
    FOR EACH ROW EXECUTE FUNCTION public.orders_cascade_delete_items();

COMMIT;

-- После переключения имя таблицы в конфигурации job'а меняется на orders:
--   Partitioning:Tables:1:Table = orders
-- Приложению менять ничего не нужно: SQL-запросы остаются прежними.

-- ---------------------------------------------------------------------
-- ОТКАТ
-- ---------------------------------------------------------------------
-- BEGIN;
-- DROP TRIGGER trg_orders_cascade_delete_items ON public.orders;
-- ALTER TABLE public.orders RENAME TO orders_partitioned;
-- ALTER TABLE public.orders_unpartitioned RENAME TO orders;
-- ALTER INDEX public."PK_orders_unpartitioned" RENAME TO "PK_orders";
-- ALTER TABLE public.order_items
--     ADD CONSTRAINT "FK_order_items_orders_order_id"
--     FOREIGN KEY (order_id) REFERENCES public.orders(id) ON DELETE CASCADE;
-- COMMIT;
