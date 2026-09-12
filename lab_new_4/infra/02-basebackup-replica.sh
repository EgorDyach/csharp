#!/usr/bin/env bash
# =====================================================================
# Часть 1-2, шаг 2: снятие базовой копии Primary для Replica
# =====================================================================
# Streaming replication начинается не с пустой базы, а с побайтовой
# копии кластера Primary: реплика обязана иметь тот же системный
# идентификатор и ту же раскладку файлов. Делает эту копию pg_basebackup.
#
# Флаги, которые здесь важны:
#   -Fp  копия в виде обычного каталога, а не tar — её сразу можно
#        подложить как PGDATA реплики;
#   -Xs  поток WAL забирается параллельно с копированием файлов, иначе
#        на большой базе нужные сегменты успеют удалиться до конца копии;
#   -R   pg_basebackup сам создаёт standby.signal и пишет primary_conninfo
#        в postgresql.auto.conf — руками конфиг править не нужно;
#   -S   копия сразу привязывается к слоту репликации.
# =====================================================================
set -euo pipefail

PRIMARY_HOST="${PRIMARY_HOST:-postgres}"
NETWORK="${NETWORK:-cproject_chakchakshop_network}"
VOLUME="${VOLUME:-cproject_postgres_replica_data}"
IMAGE="${IMAGE:-postgres:16-alpine}"
REPL_USER="${REPL_USER:-replicator}"
REPL_PASSWORD="${REPL_PASSWORD:-replicator_pwd}"
SLOT="${REPL_SLOT:-replica_1_slot}"

echo "==> Том ${VOLUME}"
docker volume create "$VOLUME" >/dev/null

echo "==> pg_basebackup с ${PRIMARY_HOST}"
docker run --rm \
    --network "$NETWORK" \
    -v "${VOLUME}:/pgdata" \
    -e PGPASSWORD="$REPL_PASSWORD" \
    "$IMAGE" \
    sh -c "
        set -e
        rm -rf /pgdata/* /pgdata/.[!.]* 2>/dev/null || true
        chown postgres:postgres /pgdata
        chmod 0700 /pgdata
        su-exec postgres pg_basebackup \
            -h '${PRIMARY_HOST}' -p 5432 -U '${REPL_USER}' \
            -D /pgdata -Fp -Xs -P -R -S '${SLOT}'
    "

echo "==> Что pg_basebackup положил в копию"
docker run --rm -v "${VOLUME}:/pgdata" "$IMAGE" \
    sh -c "ls -la /pgdata/standby.signal && cat /pgdata/postgresql.auto.conf"
