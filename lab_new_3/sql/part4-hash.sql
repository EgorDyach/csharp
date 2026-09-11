-- =====================================================================
-- Часть 6: HASH PARTITIONING
-- =====================================================================
\timing on
\set ON_ERROR_STOP off
SET search_path = lab3, public;

DROP TABLE IF EXISTS lab3.user_events CASCADE;

\echo '### 6.1 Равномерное распределение по user_id'
CREATE TABLE lab3.user_events (
    id         BIGINT      NOT NULL,
    user_id    BIGINT      NOT NULL,
    event_type VARCHAR(50),
    created_at TIMESTAMP   NOT NULL
) PARTITION BY HASH (user_id);

CREATE TABLE lab3.user_events_0 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE lab3.user_events_1 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE lab3.user_events_2 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE lab3.user_events_3 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 3);

\echo '### 6.2 Загрузка 4 000 000 событий на 200 000 пользователей'
INSERT INTO lab3.user_events (id, user_id, event_type, created_at)
SELECT g,
       (floor(random() * 200000) + 1)::bigint,
       (ARRAY['click','view','purchase'])[floor(random() * 3 + 1)::int],
       NOW() - (random() * 1460) * INTERVAL '1 day'
FROM generate_series(1, 4000000) g;
ANALYZE lab3.user_events;

\echo '### 6.3 Насколько равномерно распределились данные'
SELECT tableoid::regclass AS partition_name,
       COUNT(*),
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct
FROM lab3.user_events
GROUP BY tableoid ORDER BY partition_name;

\echo '### 6.4 Размеры партиций'
SELECT c.relname, pg_size_pretty(pg_total_relation_size(c.oid)) AS total_size
FROM pg_class c JOIN pg_inherits i ON i.inhrelid = c.oid
WHERE i.inhparent = 'lab3.user_events'::regclass ORDER BY 1;

\echo '### 6.5 HASH отсекает только при равенстве по ключу'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab3.user_events WHERE user_id = 12345;

\echo '### 6.6 ...а диапазон по ключу отсечь нельзя: hash не сохраняет порядок'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lab3.user_events WHERE user_id BETWEEN 1 AND 1000;

\echo '### 6.7 Почему HASH плох для «удалить старше 3 лет»'
--      Старые данные размазаны по всем партициям равномерно:
SELECT tableoid::regclass AS partition_name,
       count(*) FILTER (WHERE created_at < NOW() - INTERVAL '3 years') AS older_than_3y,
       count(*)                                                        AS total
FROM lab3.user_events GROUP BY tableoid ORDER BY partition_name;

--      Поэтому вместо мгновенного DROP TABLE придётся выполнять DELETE
--      по всем четырём партициям:
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM lab3.user_events WHERE created_at < NOW() - INTERVAL '3 years';
