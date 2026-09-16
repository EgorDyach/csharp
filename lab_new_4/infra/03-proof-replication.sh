#!/usr/bin/env bash
# =====================================================================
# Части 3-4: доказательство репликации и read-only поведение Replica
# =====================================================================
set -uo pipefail

P="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop"
R="docker exec chakchakshop_postgres_replica psql -U postgres -d chakchakshop"

echo "### 3.1 Кто есть кто"
echo "--- Primary:"
$P -c "SELECT inet_server_addr() AS addr,
              pg_is_in_recovery() AS in_recovery,
              current_setting('port') AS port,
              pg_current_wal_lsn() AS current_wal;"
echo "--- Replica:"
$R -c "SELECT inet_server_addr() AS addr,
              pg_is_in_recovery() AS in_recovery,
              current_setting('port') AS port,
              pg_last_wal_receive_lsn() AS received,
              pg_last_wal_replay_lsn() AS replayed;"

echo
echo "### 3.2 Состояние репликации глазами Primary"
$P -x -c "SELECT application_name, client_addr, state, sync_state,
                 sent_lsn, write_lsn, flush_lsn, replay_lsn,
                 write_lag, flush_lag, replay_lag
          FROM pg_stat_replication;"
$P -c "SELECT slot_name, slot_type, active,
              pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
       FROM pg_replication_slots;"

echo
echo "### 3.3 Запись на Primary"
$P -c "INSERT INTO categories (id, name, description, created_at)
       VALUES ('dddddddd-dddd-dddd-dddd-ddddddddddd1',
               'Реплика-тест',
               'Строка создана на Primary в ходе лабораторной №4',
               NOW())
       ON CONFLICT (id) DO UPDATE SET description = EXCLUDED.description,
                                      updated_at  = NOW()
       RETURNING id, name, created_at;"

echo
echo "### 3.4 Чтение той же строки на Replica"
$R -c "SELECT id, name, description FROM categories
       WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';"

echo
echo "### 3.5 UPDATE на Primary -> то же значение на Replica"
$P -c "UPDATE categories SET name = 'Реплика-тест ' || to_char(NOW(),'HH24:MI:SS'),
                            updated_at = NOW()
       WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1'
       RETURNING name;"
$R -c "SELECT name FROM categories WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';"

echo
echo "### 3.6 Совпадают ли объёмы данных на двух узлах"
for node in "$P" "$R"; do
    $node -c "SELECT 'orders' AS t, count(*) FROM orders
              UNION ALL SELECT 'users', count(*) FROM users
              UNION ALL SELECT 'categories', count(*) FROM categories
              ORDER BY 1;"
done

echo
echo "=========================================================="
echo "### 4.1 Часть 4: попытка записи на Replica"
echo "=========================================================="
$R -c "INSERT INTO categories (id, name, description, created_at)
       VALUES (gen_random_uuid(), 'Запись на реплике', 'так нельзя', NOW());"

echo
echo "### 4.2 UPDATE на Replica"
$R -c "UPDATE categories SET name = 'испорчено' WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';"

echo
echo "### 4.3 DELETE на Replica"
$R -c "DELETE FROM categories WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';"

echo
echo "### 4.4 Даже создание временной таблицы невозможно"
$R -c "CREATE TEMP TABLE t_probe (x int);"

echo
echo "### 4.5 Транзакция по умолчанию на Replica"
$R -c "SHOW transaction_read_only;"
$P -c "SHOW transaction_read_only;"

echo
echo "### 4.6 Читать при этом можно что угодно, включая тяжёлую аналитику"
$R -c "SELECT date_trunc('month', created_at)::date AS month, count(*)
       FROM orders
       WHERE created_at >= '2026-07-01'
       GROUP BY 1 ORDER BY 1;"
