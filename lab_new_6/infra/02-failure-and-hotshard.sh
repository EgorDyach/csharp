#!/usr/bin/env bash
# =====================================================================
# Части 6-7: отказ шарда и горячий шард
# =====================================================================
set -uo pipefail

API="http://localhost:8090/api/sharding"
KEY="X-API-Key: your-api-key-here-change-in-production"
SRC="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -tAc"

# Берём по одному обычному клиенту с каждого шарда.
U0=$($SRC "SELECT user_id FROM shardlab.user_assignment WHERE mod_3=0 AND orders_count BETWEEN 25 AND 35 ORDER BY user_id LIMIT 1;")
U2=$($SRC "SELECT user_id FROM shardlab.user_assignment WHERE mod_3=2 AND orders_count BETWEEN 25 AND 35 ORDER BY user_id LIMIT 1;")

probe() {
    local label="$1" url="$2"
    printf '  %-34s ' "$label"
    local body code
    body=$(curl -s -m 20 -o /tmp/lab6_probe.json -w '%{http_code}' -H "$KEY" "$url")
    code="$body"
    if [ "$code" = "200" ]; then
        python3 - <<'PY'
import json
d = json.load(open('/tmp/lab6_probe.json'))
bits = []
if 'shardsQueried' in d: bits.append(f"опрошено {d['shardsQueried']}")
if d.get('failedShards'): bits.append(f"УПАЛИ {len(d['failedShards'])}")
if 'complete' in d: bits.append("полный" if d['complete'] else "ЧАСТИЧНЫЙ")
if 'total' in d: bits.append(f"total={d['total']}")
if 'rows' in d: bits.append(f"строк={d['rows']}")
if 'elapsedMs' in d: bits.append(f"{d['elapsedMs']:.0f} мс")
print("200  " + ", ".join(bits))
PY
    else
        echo "$code  $(head -c 120 /tmp/lab6_probe.json)"
    fi
}

echo "=========================================================="
echo "### 6. ОТКАЗ ОДНОГО SHARD"
echo "=========================================================="
echo "Клиент на shard 0: $U0"
echo "Клиент на shard 2: $U2"
echo
echo "--- Все три узла живы:"
probe "GET orders клиента с shard 0" "$API/orders/$U0?limit=5"
probe "GET orders клиента с shard 2" "$API/orders/$U2?limit=5"
probe "COUNT по всем шардам"          "$API/count"
probe "ORDER BY + LIMIT по всем"      "$API/newest?limit=10"

echo
echo "--- Гасим shard 2"
docker stop chakchakshop_shard2 >/dev/null
sleep 2
docker ps --format '{{.Names}}\t{{.Status}}' | grep shard | sort

echo
echo "--- Что работает и что нет:"
probe "GET orders клиента с shard 0" "$API/orders/$U0?limit=5"
probe "GET orders клиента с shard 2" "$API/orders/$U2?limit=5"
probe "COUNT по всем шардам"          "$API/count"
probe "ORDER BY + LIMIT по всем"      "$API/newest?limit=10"

echo
echo "--- Детали частичного ответа COUNT:"
curl -s -m 20 -H "$KEY" "$API/count" | python3 -m json.tool

echo
echo "--- Сколько данных стало недоступно:"
docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -c "
SELECT mod_3 AS shard,
       count(*) AS users, sum(orders_count) AS orders,
       round(100.0 * sum(orders_count) / sum(sum(orders_count)) OVER (), 2) AS pct_of_all
FROM shardlab.user_assignment GROUP BY mod_3 ORDER BY mod_3;"

echo
echo "--- Поднимаем shard 2 обратно"
docker start chakchakshop_shard2 >/dev/null
for i in $(seq 1 30); do
    docker exec chakchakshop_shard2 pg_isready -U postgres >/dev/null 2>&1 && break
    sleep 1
done
sleep 2
probe "COUNT после восстановления"    "$API/count"

echo
echo "=========================================================="
echo "### 7. HOT SHARD"
echo "=========================================================="
echo "--- Строки уже распределены неравномерно:"
for i in 0 1 2; do
    R=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc "SELECT count(*) FROM orders;")
    S=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc "SELECT pg_size_pretty(pg_database_size('shard'));")
    printf '    shard %d: %10s заказов, %s\n' "$i" "$R" "$S"
done

echo
echo "--- Но дело не только в строках. Одна и та же агрегация на трёх узлах:"
echo "    (три прогона на узел, берём последний — на прогретом кэше)"
for i in 0 1 2; do
    for run in 1 2 3; do
        OUT=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -c "\timing on" -c \
            "SELECT status, count(*), sum(total_amount) FROM orders GROUP BY status;" 2>&1 | grep '^Time:')
    done
    printf '    shard %d: %s\n' "$i" "$OUT"
done

echo
echo "--- Кто именно делает шард горячим:"
docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -c "
SELECT u.username, a.mod_3 AS shard, a.orders_count,
       round(100.0 * a.orders_count / (SELECT sum(orders_count) FROM shardlab.user_assignment), 2) AS pct_of_all_orders
FROM shardlab.user_assignment a JOIN users u ON u.id = a.user_id
ORDER BY a.orders_count DESC LIMIT 3;"

echo
echo "--- Запрос по одному ключу, который кладёт целый узел:"
WHALE=$($SRC "SELECT user_id FROM shardlab.user_assignment ORDER BY orders_count DESC LIMIT 1;")
WSHARD=$($SRC "SELECT mod_3 FROM shardlab.user_assignment WHERE user_id='$WHALE';")
echo "    клиент-гигант лежит на shard $WSHARD"
docker exec "chakchakshop_shard${WSHARD}" psql -U postgres -d shard -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount) FROM orders WHERE user_id = '$WHALE';"

echo
echo "--- Тот же запрос для обычного клиента на том же узле:"
NORMAL=$($SRC "SELECT user_id FROM shardlab.user_assignment WHERE mod_3=$WSHARD AND orders_count BETWEEN 25 AND 35 ORDER BY user_id LIMIT 1;")
docker exec "chakchakshop_shard${WSHARD}" psql -U postgres -d shard -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*), sum(total_amount) FROM orders WHERE user_id = '$NORMAL';"
