#!/usr/bin/env bash
# =====================================================================
# Часть 6: replication lag — попытка увидеть момент, когда Primary
#          уже содержит новое значение, а Replica ещё нет
# =====================================================================
set -uo pipefail

P="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop"
R="docker exec chakchakshop_postgres_replica psql -U postgres -d chakchakshop"
PQ="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -tAc"
RQ="docker exec chakchakshop_postgres_replica psql -U postgres -d chakchakshop -tAc"

echo "### 6.1 Опыт первый: одиночная запись в спокойной системе"
echo "--- пишем на Primary и сразу читаем на Replica"
$PQ "INSERT INTO categories (id, name, description, created_at)
     VALUES ('dddddddd-dddd-dddd-dddd-ddddddddddd2','lag-probe-1','',NOW())
     ON CONFLICT (id) DO UPDATE SET name = 'lag-probe-' || clock_timestamp()
     RETURNING name;"
$RQ "SELECT name FROM categories WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd2';"
echo "--- отставание в этот момент:"
$P -c "SELECT pg_wal_lsn_diff(sent_lsn, replay_lsn) AS replay_lag_bytes,
              write_lag, flush_lag, replay_lag
       FROM pg_stat_replication;"
echo
echo "  Поймать окно так не получится: одно docker exec стоит ~100 мс,"
echo "  а репликация внутри одного хоста укладывается в доли миллисекунды."
echo "  Нужен либо поток записи, либо искусственная задержка. Делаем оба."

echo
echo "=========================================================="
echo "### 6.2 Опыт второй: отставание под нагрузкой записи"
echo "=========================================================="
$PQ "CREATE SCHEMA IF NOT EXISTS lab4;" >/dev/null
$PQ "DROP TABLE IF EXISTS lab4.wal_load;" >/dev/null
$PQ "CREATE TABLE lab4.wal_load (id bigint, payload text, created_at timestamptz);" >/dev/null
sleep 1

echo "--- 6.2a одна большая транзакция: 3 000 000 строк одним INSERT"
docker exec -d chakchakshop_postgres psql -U postgres -d chakchakshop -c \
  "INSERT INTO lab4.wal_load
   SELECT g, repeat('x', 200), NOW() FROM generate_series(1, 3000000) g;"

echo "--- пока она идёт, сравниваем узлы каждые 0.4 с"
printf '%-10s | %12s | %12s | %10s | %14s\n' "время" "Primary" "Replica" "разница" "WAL-отставание"
printf -- '-----------+--------------+--------------+------------+----------------\n'
for i in $(seq 1 14); do
    PRIMARY_ROWS=$($PQ "SELECT count(*) FROM lab4.wal_load;" 2>/dev/null || echo "-")
    REPLICA_ROWS=$($RQ "SELECT count(*) FROM lab4.wal_load;" 2>/dev/null || echo "0")
    LAG=$($PQ "SELECT coalesce(pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)),'-')
               FROM pg_stat_replication LIMIT 1;" 2>/dev/null || echo "-")
    DIFF=$(( ${PRIMARY_ROWS:-0} - ${REPLICA_ROWS:-0} ))
    printf '%-10s | %12s | %12s | %10s | %14s\n' \
        "$(date -u +%H:%M:%S)" "$PRIMARY_ROWS" "$REPLICA_ROWS" "$DIFF" "$LAG"
    sleep 0.4
done

echo
echo "--- после завершения записи узлы сходятся"
sleep 6
printf 'Primary: %s\nReplica: %s\n' \
    "$($PQ 'SELECT count(*) FROM lab4.wal_load;')" \
    "$($RQ 'SELECT count(*) FROM lab4.wal_load;')"

echo
echo "  Счётчики строк всё время совпадали, хотя отставание по WAL доходило"
echo "  до десятков мегабайт. Причина в том, что вся вставка была ОДНОЙ"
echo "  транзакцией: до COMMIT её не видит ни Primary, ни Replica."
echo "  Отставание реально было — просто оно не проявлялось в данных."
echo
echo "--- 6.2b много мелких транзакций: 60 отдельных INSERT по 50 000 строк"
$PQ "TRUNCATE lab4.wal_load;" >/dev/null
docker exec -d chakchakshop_postgres sh -c \
  'for i in $(seq 1 60); do
       psql -U postgres -d chakchakshop -q -c \
       "INSERT INTO lab4.wal_load SELECT g, repeat(chr(97+(g%26)),200), NOW()
        FROM generate_series(1,50000) g;"
   done'

# Замер делается «в скобках»: счётчик Primary читается до и после чтения
# Replica. Если оба значения совпали, за время опроса на Primary ничего
# не закоммитилось, и разницу можно считать честной. Иначе выборка
# грязная — между двумя запросами проехала ещё пачка строк, и наивное
# вычитание даёт бессмыслицу вплоть до отрицательных чисел.
printf '%-10s | %12s | %12s | %10s | %14s | %s\n' "время" "Primary" "Replica" "разница" "WAL-отставание" "замер"
printf -- '-----------+--------------+--------------+------------+----------------+---------\n'
MAXDIFF=0
for i in $(seq 1 24); do
    P1=$($PQ "SELECT count(*) FROM lab4.wal_load;" 2>/dev/null || echo 0)
    REPLICA_ROWS=$($RQ "SELECT count(*) FROM lab4.wal_load;" 2>/dev/null || echo 0)
    P2=$($PQ "SELECT count(*) FROM lab4.wal_load;" 2>/dev/null || echo 0)
    LAG=$($PQ "SELECT coalesce(pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)),'-')
               FROM pg_stat_replication LIMIT 1;" 2>/dev/null || echo "-")

    if [ "$P1" = "$P2" ]; then
        DIFF=$(( P1 - REPLICA_ROWS ))
        MARK="чистый"
        [ "$DIFF" -gt "$MAXDIFF" ] && MAXDIFF=$DIFF
    else
        DIFF="?"
        MARK="грязный"
    fi
    printf '%-10s | %12s | %12s | %10s | %14s | %s\n' \
        "$(date -u +%H:%M:%S)" "$P1" "$REPLICA_ROWS" "$DIFF" "$LAG" "$MARK"
done
echo "максимальное честно замеренное расхождение строк: ${MAXDIFF}"

echo
echo "=========================================================="
echo "### 6.3 Опыт третий: детерминированное окно рассинхронизации"
echo "=========================================================="
echo "  recovery_min_apply_delay заставляет Replica придержать применение"
echo "  уже полученного WAL. Это штатный параметр: так делают реплику,"
echo "  отстающую на час, чтобы успеть отменить ошибочный DELETE."
echo
echo "--- включаем задержку 15 секунд на Replica"
$R -c "ALTER SYSTEM SET recovery_min_apply_delay = '15s';"
$R -c "SELECT pg_reload_conf();" >/dev/null
sleep 1
$R -c "SHOW recovery_min_apply_delay;"

echo
echo "--- пишем на Primary"
STAMP=$(date -u +%H:%M:%S)
$PQ "UPDATE categories SET name = 'delayed-${STAMP}', updated_at = NOW()
     WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd2';" >/dev/null
echo "Primary отдаёт:  $($PQ "SELECT name FROM categories WHERE id='dddddddd-dddd-dddd-dddd-ddddddddddd2';")"
echo "Replica отдаёт:  $($RQ "SELECT name FROM categories WHERE id='dddddddd-dddd-dddd-dddd-ddddddddddd2';")"
echo "                 ^^^ вот оно: старое значение при уже записанном новом"

echo
echo "--- измеряем отставание, пока оно есть"
$P -c "SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS behind_bytes,
              replay_lag
       FROM pg_stat_replication;"
$R -c "SELECT pg_last_wal_receive_lsn() AS received,
              pg_last_wal_replay_lsn()  AS replayed,
              now() - pg_last_xact_replay_timestamp() AS behind_time;"

echo
echo "--- ждём и смотрим, как значение догоняет"
for i in 1 2 3 4 5 6; do
    printf '%s  replica: %s\n' "$(date -u +%H:%M:%S)" \
        "$($RQ "SELECT name FROM categories WHERE id='dddddddd-dddd-dddd-dddd-ddddddddddd2';")"
    sleep 3
done

echo
echo "--- снимаем задержку"
$R -c "ALTER SYSTEM RESET recovery_min_apply_delay;"
$R -c "SELECT pg_reload_conf();" >/dev/null
sleep 2
$R -c "SHOW recovery_min_apply_delay;"

echo
echo "=========================================================="
echo "### 6.4 Чем мерить отставание в проде"
echo "=========================================================="
echo "--- со стороны Primary: сколько байт WAL реплика ещё не применила"
$P -c "SELECT application_name, client_addr, state, sync_state,
              pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), sent_lsn))   AS not_sent,
              pg_size_pretty(pg_wal_lsn_diff(sent_lsn, flush_lsn))              AS not_flushed,
              pg_size_pretty(pg_wal_lsn_diff(flush_lsn, replay_lsn))            AS not_replayed,
              write_lag, flush_lag, replay_lag
       FROM pg_stat_replication;"
echo "--- со стороны Replica: на сколько секунд она позади"
$R -c "SELECT pg_is_in_recovery() AS in_recovery,
              pg_last_wal_receive_lsn() AS received,
              pg_last_wal_replay_lsn()  AS replayed,
              pg_last_xact_replay_timestamp() AS last_applied_tx,
              now() - pg_last_xact_replay_timestamp() AS behind_time;"

echo
echo "--- убираем нагрузочную таблицу"
$PQ "DROP TABLE IF EXISTS lab4.wal_load;" >/dev/null
echo "готово"
