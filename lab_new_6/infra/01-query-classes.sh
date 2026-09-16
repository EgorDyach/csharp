#!/usr/bin/env bash
# =====================================================================
# Части 2-5: классы запросов после шардирования
# =====================================================================
# Кластер из лабораторной №5: три независимых PostgreSQL, 5 000 005
# заказов, ключ шардирования — user_id.
# =====================================================================
set -uo pipefail

API="http://localhost:8090/api/sharding"
KEY="X-API-Key: your-api-key-here-change-in-production"
SRC="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -tAc"

s0() { docker exec chakchakshop_shard0 psql -U postgres -d shard "$@"; }
s1() { docker exec chakchakshop_shard1 psql -U postgres -d shard "$@"; }
s2() { docker exec chakchakshop_shard2 psql -U postgres -d shard "$@"; }

echo "=========================================================="
echo "### 2. SINGLE-SHARD QUERY"
echo "=========================================================="
# Берём обычного клиента: не кита и не пустого.
USER_ID=$($SRC "SELECT user_id FROM shardlab.user_assignment
                WHERE orders_count BETWEEN 25 AND 35 ORDER BY user_id LIMIT 1;")
SHARD=$($SRC "SELECT mod_3 FROM shardlab.user_assignment WHERE user_id='$USER_ID';")
echo "Клиент $USER_ID, роутер говорит: shard $SHARD"
echo
echo "--- запрос сервиса GET /api/orders/my после шардирования:"
curl -s -H "$KEY" "$API/orders/$USER_ID?limit=5" | python3 -m json.tool | head -14

echo
echo "--- тот же запрос напрямую к шарду, с планом:"
docker exec "chakchakshop_shard${SHARD}" psql -U postgres -d shard -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, total_amount, status, created_at FROM orders
WHERE user_id = '$USER_ID' ORDER BY created_at DESC LIMIT 20;"

echo
echo "--- а на остальных узлах этого клиента просто нет:"
for i in 0 1 2; do
    CNT=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc \
        "SELECT count(*) FROM orders WHERE user_id='$USER_ID';")
    printf '    shard %d: %s заказов\n' "$i" "$CNT"
done

echo
echo "=========================================================="
echo "### 3. АГРЕГИРУЮЩИЙ ЗАПРОС"
echo "=========================================================="
echo "--- время каждого узла по отдельности на SELECT count(*)"
for i in 0 1 2; do
    T=$( { /usr/bin/time -p docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc \
          "SELECT count(*) FROM orders;" ; } 2>&1 | tr '\n' ' ')
    echo "    shard $i: $T"
done

echo
echo "--- тот же COUNT через сервис: опрашиваются все три, сумма считается в приложении"
curl -s -H "$KEY" "$API/count" | python3 -m json.tool

echo
echo "--- агрегация посложнее: выручка по статусам, на каждом узле свой кусок"
for i in 0 1 2; do
    echo "  shard $i:"
    docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -c \
      "SELECT status, count(*) AS orders, round(sum(total_amount)) AS revenue
       FROM orders GROUP BY status ORDER BY status;"
done
echo "  ^^^ три частичных ответа, которые кто-то обязан сложить."
echo "      PostgreSQL этого сделать не может: он не видит соседей."

echo
echo "=========================================================="
echo "### 4. JOIN"
echo "=========================================================="
echo "--- JOIN заказа с позициями и товарами внутри одного шарда:"
curl -s -H "$KEY" "$API/orders/$USER_ID/items?limit=3" | python3 -m json.tool | head -20

echo
echo "--- почему он локальный: позиции заказа лежат на том же узле"
docker exec "chakchakshop_shard${SHARD}" psql -U postgres -d shard -c "
EXPLAIN (ANALYZE, BUFFERS)
SELECT o.id, p.name, oi.quantity
FROM orders o
JOIN order_items oi ON oi.order_id = o.id AND oi.user_id = o.user_id
JOIN products p     ON p.id = oi.product_id
WHERE o.user_id = '$USER_ID'
LIMIT 20;" 2>&1 | head -20

echo
echo "--- контрфактический опыт: а если бы orders шардировали по id заказа?"
echo "    Тогда заказы одного клиента размазались бы по узлам, и главный"
echo "    запрос сервиса перестал бы быть single-shard. Считаем, по скольким"
echo "    узлам разъехались бы заказы каждого клиента."
docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -c "
WITH spread AS (
    SELECT o.user_id,
           count(DISTINCT shardlab.shard_by_modulo(o.id::text, 3)) AS shards_touched
    FROM orders o
    GROUP BY o.user_id
)
SELECT shards_touched AS shards_per_user, count(*) AS users,
       round(100.0 * count(*) / sum(count(*)) OVER (), 2) AS pct
FROM spread GROUP BY 1 ORDER BY 1;"
echo "  ^^^ вот во что превратился бы GET /api/orders/my при ключе id."

echo
echo "--- а почему не product_id: кардинальность"
docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -c "
SELECT count(*) AS products_total FROM products;"
docker exec chakchakshop_postgres psql -U postgres -d chakchakshop -c "
SELECT product_id, count(*) AS items,
       round(100.0 * count(*) / sum(count(*)) OVER (), 4) AS pct
FROM order_items GROUP BY 1 ORDER BY 2 DESC;"
echo "  ^^^ семь товаров на весь каталог, и два из них держат почти всё."
echo "      Такой ключ не делится даже на три узла: шардов получилось бы"
echo "      столько, сколько товаров, а нагрузка легла бы на два из них."

echo
echo "=========================================================="
echo "### 5. ORDER BY + LIMIT"
echo "=========================================================="
echo "--- что отдаёт каждый узел как свои 5 самых свежих заказов:"
for i in 0 1 2; do
    echo "  shard $i:"
    docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -c \
      "SELECT id, created_at FROM orders ORDER BY created_at DESC LIMIT 5;"
done

echo
echo "--- глобальный top-20 после слияния в приложении:"
curl -s -H "$KEY" "$API/newest?limit=20" > /tmp/lab6_newest.json
python3 - <<'PY'
import json, collections, subprocess
d = json.load(open('/tmp/lab6_newest.json'))
print(f"  опрошено шардов: {d['shardsQueried']}, время {d['elapsedMs']:.1f} мс")
owners = collections.Counter()
for row in d['data']:
    shard = subprocess.run(
        ["docker","exec","chakchakshop_postgres","psql","-U","postgres","-d","chakchakshop","-tAc",
         f"SELECT mod_3 FROM shardlab.user_assignment WHERE user_id='{row['userId']}'"],
        capture_output=True, text=True).stdout.strip()
    owners[shard] += 1
print("  откуда пришли строки глобального top-20:")
for shard, n in sorted(owners.items()):
    print(f"    shard {shard}: {n} из 20")
print()
print("  ^^^ если бы взяли top-20 только с одного узла, потеряли бы",
      20 - max(owners.values()), "из 20 правильных строк.")
PY
