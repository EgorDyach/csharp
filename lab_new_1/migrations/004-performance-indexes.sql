--liquibase formatted sql

-- Индексы добавлены по результатам лабораторной работы №1
-- (docs/lab-01-indexes.md, задания 27-29). Каждый подтверждён
-- измерением EXPLAIN ANALYZE до и после на 1 000 000 заказов.

--changeset system:020-index-orders-user-id-created-at
-- Закрывает GET /api/orders/my: WHERE user_id = ? ORDER BY created_at DESC LIMIT ?
-- Порядок колонок обязателен: user_id первым (условие равенства),
-- created_at DESC вторым (порядок сортировки).
-- Замер: 34.5 мс -> 0.026 мс, прочитано страниц 11 034 -> 23.
CREATE INDEX IF NOT EXISTS "IX_orders_user_id_created_at"
    ON orders (user_id, created_at DESC);
--rollback DROP INDEX IF EXISTS "IX_orders_user_id_created_at";

--changeset system:021-index-orders-created-at
-- Закрывает GET /api/orders: ORDER BY created_at DESC LIMIT ? OFFSET ?
-- Замер: 34.5 мс -> 0.012 мс, прочитано страниц 11 034 -> 13.
CREATE INDEX IF NOT EXISTS "IX_orders_created_at"
    ON orders (created_at DESC);
--rollback DROP INDEX IF EXISTS "IX_orders_created_at";

-- Сознательно НЕ добавлен индекс (user_id, status, created_at DESC):
-- на замере он не ускорил выборку (0.032 мс против 0.045 мс), но стоит 54 MB
-- и замедляет запись. При текущей нагрузке не окупается.
