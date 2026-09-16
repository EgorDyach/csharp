#!/usr/bin/env bash
# =====================================================================
# Части 5 и 7: расширение кластера 3 -> 4 узла, вживую
# =====================================================================
# Считать проценты в SQL — одно, физически перевезти данные — другое.
# Здесь на shard3 переносится ровно то, что должно переехать по каждой
# из двух стратегий, и замеряется, сколько это стоит.
# =====================================================================
set -uo pipefail

SRC="chakchakshop_postgres"
SRC_DB="chakchakshop"
NEW="chakchakshop_shard3"

move_for() {
    local col="$1" label="$2"

    docker exec "$NEW" psql -U postgres -d shard -q -c "TRUNCATE orders, order_items;"

    local started=$(date +%s.%N)
    docker exec "$SRC" psql -U postgres -d "$SRC_DB" -Atc "
        COPY (
            SELECT o.id, o.user_id, o.total_amount, o.status, o.created_at, o.updated_at
            FROM orders o
            JOIN shardlab.user_assignment a ON a.user_id = o.user_id
            WHERE a.${col} = 3
        ) TO STDOUT" \
      | docker exec -i "$NEW" psql -U postgres -d shard -q -c "COPY orders FROM STDIN"
    local finished=$(date +%s.%N)

    local moved=$(docker exec "$NEW" psql -U postgres -d shard -tAc "SELECT count(*) FROM orders;")
    local size=$(docker exec "$NEW" psql -U postgres -d shard -tAc "SELECT pg_size_pretty(pg_total_relation_size('orders'));")
    local secs=$(python3 -c "print(f'{$finished - $started:.1f}')")

    printf '%-22s перевезено %10s заказов, %8s, время %6s с\n' "$label" "$moved" "$size" "$secs"
}

echo "### Физический переезд на четвёртый узел"
echo
echo "--- Стратегия hash(key) % N: на shard3 уезжает всё, чей остаток стал равен 3"
move_for "mod_4" "hash(key) % 4"

echo
echo "--- Стратегия Consistent Hashing: на shard3 уезжает только участок кольца"
move_for "ring_4" "consistent hashing"

echo
echo "### Но переехавшие на shard3 — это лишь часть работы."
echo "### При hash % N данные ещё и тасуются между старыми узлами."
docker exec "$SRC" psql -U postgres -d "$SRC_DB" -c "
    SELECT 'hash % N'  AS strategy,
           sum(orders_count) FILTER (WHERE mod_3 <> mod_4 AND mod_4 <> 3)  AS reshuffled_between_old_nodes,
           sum(orders_count) FILTER (WHERE mod_4 = 3)                      AS moved_to_new_node,
           sum(orders_count) FILTER (WHERE mod_3 <> mod_4)                 AS total_moved
    FROM shardlab.user_assignment
    UNION ALL
    SELECT 'Consistent Hashing',
           sum(orders_count) FILTER (WHERE ring_3 <> ring_4 AND ring_4 <> 3),
           sum(orders_count) FILTER (WHERE ring_4 = 3),
           sum(orders_count) FILTER (WHERE ring_3 <> ring_4)
    FROM shardlab.user_assignment;"

echo
echo "--- Возвращаем shard3 в исходное пустое состояние"
docker exec "$NEW" psql -U postgres -d shard -q -c "TRUNCATE orders, order_items;"
docker exec "$NEW" psql -U postgres -d shard -c "SELECT count(*) AS orders_on_shard3 FROM orders;"
