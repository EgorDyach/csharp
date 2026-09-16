#!/usr/bin/env bash
# =====================================================================
# Часть 5: реальное чтение сервиса обслуживается Replica
# =====================================================================
set -uo pipefail

API="http://localhost:8090"
KEY="X-API-Key: your-api-key-here-change-in-production"
TOKEN="$(cat /tmp/lab4_token 2>/dev/null || true)"

P="docker exec chakchakshop_postgres psql -U postgres -d chakchakshop"
R="docker exec chakchakshop_postgres_replica psql -U postgres -d chakchakshop"
RQ="docker exec chakchakshop_postgres_replica psql -U postgres -d chakchakshop -tAc"

echo "### 5.1 Куда сервис открывает подключения"
curl -s -H "$KEY" "$API/api/replication/where-am-i" | python3 -m json.tool

echo
echo "### 5.2 Заголовок ответа на каждой ручке"
for path in "api/orders?pageNumber=1&pageSize=5" "api/orders/my?pageNumber=1&pageSize=5"; do
    NODE=$(curl -s -D- -o /dev/null -H "Authorization: Bearer $TOKEN" "$API/$path" | tr -d '\r' | awk -F': ' '/^X-Db-Node/{print $2}')
    printf '  GET /%-45s -> X-Db-Node: %s\n' "${path%%\?*}" "$NODE"
done
ORDER_ID=$($P -tAc "SELECT id FROM orders ORDER BY created_at DESC LIMIT 1;")
NODE=$(curl -s -D- -o /dev/null -H "Authorization: Bearer $TOKEN" "$API/api/orders/$ORDER_ID" | tr -d '\r' | awk -F': ' '/^X-Db-Node/{print $2}')
printf '  GET /%-45s -> X-Db-Node: %s\n' "api/orders/{id}" "$NODE"

echo
echo "### 5.3 Доказательство со стороны Replica: счётчик прочитанных строк"
BEFORE=$($RQ "SELECT tup_returned FROM pg_stat_database WHERE datname='chakchakshop';")
echo "  tup_returned на Replica до нагрузки: $BEFORE"
echo "  шлём 30 запросов GET /api/orders"
for i in $(seq 1 30); do
    curl -s -o /dev/null -H "Authorization: Bearer $TOKEN" "$API/api/orders?pageNumber=$i&pageSize=20"
done
AFTER=$($RQ "SELECT tup_returned FROM pg_stat_database WHERE datname='chakchakshop';")
echo "  tup_returned на Replica после:       $AFTER"
echo "  прочитано строк на Replica:          $(( AFTER - BEFORE ))"

echo
echo "### 5.4 Подключения сервиса, видимые на Replica"
$R -c "SELECT application_name, state, backend_type,
              count(*) OVER (PARTITION BY application_name) AS conns
       FROM pg_stat_activity
       WHERE datname = 'chakchakshop' AND application_name <> ''
       ORDER BY application_name;"

echo
echo "### 5.5 Запись по-прежнему идёт только на Primary"
echo "  создаём заказ через POST /api/orders"
CUSTOMER_TOKEN=$(curl -s -X POST "$API/api/auth/login" -H 'Content-Type: application/json' \
    -d '{"email":"customer@example.com","password":"Lab4Pass!2026"}' \
    | python3 -c "import sys,json;print(json.load(sys.stdin)['token'])" 2>/dev/null)
PRODUCT_ID=$($P -tAc "SELECT id FROM products ORDER BY name LIMIT 1;")
CREATED=$(curl -s -X POST "$API/api/orders" \
    -H "Authorization: Bearer $CUSTOMER_TOKEN" -H 'Content-Type: application/json' \
    -d "{\"items\":[{\"productId\":\"$PRODUCT_ID\",\"quantity\":1}]}")
echo "  ответ: $(echo "$CREATED" | head -c 200)"

echo
echo "  Replica по-прежнему read-only — сервис физически не может писать туда:"
$R -c "INSERT INTO categories (id, name, description, created_at)
       VALUES (gen_random_uuid(), 'из сервиса', '', NOW());"

echo
echo "### 5.6 Демонстрация read-your-writes через API"
curl -s -X POST -H "$KEY" "$API/api/replication/lag-demo" | python3 -m json.tool
