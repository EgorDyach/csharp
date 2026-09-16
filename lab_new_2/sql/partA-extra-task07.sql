-- ============================================================================
-- Лабораторная работа №2. Дополнение к заданию 7.
--
-- На равномерных данных у user_id = 123 всего ~113 событий из 10 млн.
-- Сортировать нечего, поэтому планировщик выбирает Bitmap + Sort даже при
-- наличии составного индекса, и операция Sort из плана не исчезает.
-- Чтобы задание имело смысл, нужен пользователь с большим числом событий —
-- ровно тот случай, ради которого составной индекс и создают.
-- ============================================================================

\echo ''
\echo '================================================================'
\echo ' Добавляем активного пользователя (user_id = 1) с 200 000 событий'
\echo '================================================================'
INSERT INTO events (user_id, event_type, payload, created_at)
SELECT 1,
       CASE WHEN random() < 0.4 THEN 'MESSAGE' WHEN random() < 0.7 THEN 'LOGIN'
            WHEN random() < 0.9 THEN 'PURCHASE' ELSE 'OTHER' END,
       '{}'::jsonb,
       (SELECT max(created_at) FROM events) - (random() * INTERVAL '365 days')
FROM generate_series(1, 200000);

VACUUM ANALYZE events;
SELECT count(*) AS total_rows FROM events;
SELECT count(*) AS active_user_rows FROM events WHERE user_id = 1;

\echo ''
\echo '--- 7.4 ДО составного индекса (он временно скрыт) -> ожидаем Sort ---'
BEGIN;
DROP INDEX idx_events_user_created;
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 1 ORDER BY created_at DESC LIMIT 100;
ROLLBACK;

\echo '--- прогрев ---'
EXPLAIN ANALYZE
SELECT * FROM events WHERE user_id = 1 ORDER BY created_at DESC LIMIT 100;
\echo '--- 7.5 ПОСЛЕ: доступен idx_events_user_created (user_id, created_at DESC) ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 1 ORDER BY created_at DESC LIMIT 100;

\echo '--- 7.6 тот же запрос без LIMIT: почему Sort возвращается ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM events WHERE user_id = 1 ORDER BY created_at DESC;
