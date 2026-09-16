-- =====================================================================
-- Части 2 и 6: запросы для наблюдения за репликацией
-- =====================================================================

-- --- НА PRIMARY -------------------------------------------------------

-- Кто подключён как standby и в каком состоянии
SELECT application_name,
       client_addr,
       state,                -- streaming = поток WAL идёт
       sync_state,           -- async / sync / quorum
       sent_lsn,             -- докуда Primary отправил
       write_lsn,            -- докуда реплика записала в свой WAL
       flush_lsn,            -- докуда сбросила на диск
       replay_lsn,           -- докуда ПРИМЕНИЛА (именно это видно в SELECT)
       write_lag, flush_lag, replay_lag
FROM pg_stat_replication;

-- Отставание в байтах по каждой стадии
SELECT application_name,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))   AS not_sent,
       pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn))              AS not_flushed,
       pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn))            AS not_replayed,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS total_behind
FROM pg_stat_replication;

-- Слот репликации: сколько WAL Primary держит ради реплики.
-- Если реплика отвалилась надолго, этот объём растёт и способен
-- заполнить диск Primary — за слотами нужен мониторинг.
SELECT slot_name, slot_type, active,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;

-- --- НА REPLICA -------------------------------------------------------

-- Роль узла: true только на standby
SELECT pg_is_in_recovery();

-- Насколько реплика позади
SELECT pg_last_wal_receive_lsn()              AS received,
       pg_last_wal_replay_lsn()               AS replayed,
       pg_last_xact_replay_timestamp()        AS last_applied_tx,
       now() - pg_last_xact_replay_timestamp() AS behind_time;
-- Осторожно с behind_time: в простое, когда на Primary нет новых
-- транзакций, эта величина растёт сама по себе, хотя реплика
-- ничего не пропустила. Метрика осмысленна только под потоком записи.

-- Приложение, читающее с реплики
SELECT application_name, state, backend_type, query_start, left(query, 60) AS query
FROM pg_stat_activity
WHERE datname = 'chakchakshop' AND application_name <> ''
ORDER BY application_name;

-- Сколько строк реплика уже отдала клиентам
SELECT datname, xact_commit, tup_returned, tup_fetched
FROM pg_stat_database WHERE datname = 'chakchakshop';
