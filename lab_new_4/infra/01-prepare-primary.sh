#!/usr/bin/env bash
# =====================================================================
# Часть 1-2, шаг 1: подготовка Primary к streaming replication
# =====================================================================
# Образ postgres:16-alpine уже приходит с wal_level = replica,
# max_wal_senders = 10 и hot_standby = on — трогать postgresql.conf
# не требуется. Не хватает только двух вещей:
#   1) роли с правом REPLICATION;
#   2) строки в pg_hba.conf, разрешающей репликационные подключения
#      с других хостов. Обычное "host all all all" её не покрывает:
#      псевдо-база replication не входит в "all".
# =====================================================================
set -euo pipefail

PRIMARY="${PRIMARY_CONTAINER:-chakchakshop_postgres}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator_pwd}"
SLOT="${REPL_SLOT:-replica_1_slot}"

echo "==> Роль ${REPL_USER}"
# -i обязателен: без него docker exec не пробрасывает stdin и heredoc
# до psql не доезжает — команда молча ничего не делает.
docker exec -i "$PRIMARY" psql -U postgres -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${REPL_USER}') THEN
        CREATE ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASSWORD}';
    ELSE
        ALTER ROLE ${REPL_USER} WITH REPLICATION LOGIN PASSWORD '${REPL_PASSWORD}';
    END IF;
END \$\$;
SQL

echo "==> Слот репликации ${SLOT}"
# Слот заставляет Primary хранить WAL, пока реплика его не заберёт.
# Без слота реплика, отставшая сильнее чем на wal_keep_size, теряет
# нужные сегменты и больше не может догнать Primary.
docker exec "$PRIMARY" psql -U postgres -v ON_ERROR_STOP=1 -c \
    "SELECT pg_create_physical_replication_slot('${SLOT}')
     WHERE NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '${SLOT}');"

echo "==> Правило в pg_hba.conf"
docker exec "$PRIMARY" sh -c "
    grep -q 'host replication ${REPL_USER} all' /var/lib/postgresql/data/pg_hba.conf ||
    echo 'host replication ${REPL_USER} all scram-sha-256' >> /var/lib/postgresql/data/pg_hba.conf
"
docker exec "$PRIMARY" psql -U postgres -c "SELECT pg_reload_conf();" >/dev/null

echo "==> Итог"
docker exec "$PRIMARY" psql -U postgres -c \
    "SELECT name, setting FROM pg_settings
     WHERE name IN ('wal_level','max_wal_senders','max_replication_slots','hot_standby');"
docker exec "$PRIMARY" psql -U postgres -c \
    "SELECT slot_name, slot_type, active FROM pg_replication_slots;"
docker exec "$PRIMARY" sh -c "tail -3 /var/lib/postgresql/data/pg_hba.conf"
