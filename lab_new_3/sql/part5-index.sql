-- =====================================================================
-- Часть 8-9: партиционирование + индексы, и где партиционирование
--            бессильно
-- =====================================================================
\timing on
\set ON_ERROR_STOP off
SET search_path = lab3, public;

\echo '### 8.0 Базовая линия: запрос по user_id без индексов'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.events
WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'
  AND user_id = 12345;

\echo '### 8.1 Индекс создаётся на РОДИТЕЛЬСКОЙ таблице'
CREATE INDEX idx_events_user_id ON lab3.events (user_id);

\echo '### 8.2 ...а физически появляется в каждой партиции (локальные индексы)'
SELECT c.relname AS index_name,
       c.relkind,
       i.indrelid::regclass AS on_table,
       pg_size_pretty(pg_relation_size(c.oid)) AS size
FROM pg_class c
LEFT JOIN pg_index i ON i.indexrelid = c.oid
WHERE c.relname LIKE 'idx_events_user_id%'
   OR c.relname LIKE '%_user_id_idx'
ORDER BY 1;

SELECT inhparent::regclass AS parent_index, inhrelid::regclass AS child_index
FROM pg_inherits
WHERE inhparent = 'lab3.idx_events_user_id'::regclass;

\echo '### 8.3 Задание: pruning + индекс вместе'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.events
WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'
  AND user_id = 12345;

\echo '### 8.4 Тот же индекс без ограничения по ключу партиционирования'
--      pruning не работает -> приходится обойти локальные индексы всех партиций
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.events WHERE user_id = 12345;

-- =====================================================================
-- Часть 9. Когда партиционирование не помогает
-- =====================================================================
\echo '### 9.1 Запрос не по ключу партиционирования: ДО индекса'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'click';

\echo '### 9.2 Создаём индекс по event_type'
CREATE INDEX idx_events_event_type ON lab3.events (event_type);
ANALYZE lab3.events;

\echo '### 9.3 ПОСЛЕ индекса'
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'click';

\echo '### 9.4 Низкоселективный запрос индексом не лечится, лечится покрытием'
CREATE INDEX idx_events_event_type_covering ON lab3.events (event_type) INCLUDE (created_at);
ANALYZE lab3.events;
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'click';

\echo '### 9.5 А вот селективный event_type индексом лечится отлично'
SELECT event_type, count(*) FROM lab3.events GROUP BY event_type ORDER BY 2 DESC;
INSERT INTO lab3.events
SELECT 950000000 + g, g, 'refund', 'rare', '2026-09-10 12:00:00'::timestamp
FROM generate_series(1, 300) g;
ANALYZE lab3.events;
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'refund';

\echo '### 9.6 Размер индексов против размера данных'
SELECT
    pg_size_pretty(SUM(pg_relation_size(c.oid)))   AS heap_total,
    pg_size_pretty(SUM(pg_indexes_size(c.oid)))    AS indexes_total
FROM pg_class c JOIN pg_inherits i ON i.inhrelid = c.oid
WHERE i.inhparent = 'lab3.events'::regclass;

\echo '### 9.7 Чего индекс не умеет, а партиция умеет: мгновенное удаление'
CREATE TABLE lab3.events_2026_09_08 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-08') TO ('2026-09-09');
INSERT INTO lab3.events (id, user_id, event_type, payload, created_at)
SELECT 800000000 + g, g, 'click', 'old', '2026-09-08 12:00:00'::timestamp
FROM generate_series(1, 1000000) g;
SELECT pg_size_pretty(pg_total_relation_size('lab3.events_2026_09_08')) AS dropping_this;
-- миллион строк исчезает за единицы миллисекунд, без VACUUM и без раздувания
DROP TABLE lab3.events_2026_09_08;
