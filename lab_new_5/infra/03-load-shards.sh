#!/usr/bin/env bash
# =====================================================================
# Часть 4: физическая раскладка данных сервиса по шардам
# =====================================================================
# Шарды — независимые экземпляры PostgreSQL, между ними нет ни FDW,
# ни репликации. Поэтому перенос идёт потоком: исходная база отдаёт
# COPY ... TO STDOUT, шард принимает COPY ... FROM STDIN. Ровно так же
# это делают настоящие миграции данных между узлами.
#
# Номер шарда вычисляет та же функция shardlab.shard_by_modulo, которую
# использует роутер в сервисе, — иначе данные легли бы не туда, куда
# потом пойдёт запрос.
#
# Использование:  ./03-load-shards.sh [strategy] [shard_count]
#   strategy:     modulo (по умолчанию) | ring
#   shard_count:  3 (по умолчанию) | 4
# =====================================================================
set -uo pipefail

STRATEGY="${1:-modulo}"
SHARDS="${2:-3}"
SRC="chakchakshop_postgres"
SRC_DB="chakchakshop"

case "$STRATEGY" in
    modulo) FN="shardlab.shard_by_modulo" ;;
    ring)   FN="shardlab.shard_by_ring"   ;;
    *) echo "неизвестная стратегия: $STRATEGY"; exit 1 ;;
esac

echo "=== Раскладка: стратегия $STRATEGY, шардов $SHARDS"

for i in $(seq 0 $((SHARDS - 1))); do
    NODE="chakchakshop_shard${i}"
    echo
    echo "--- shard $i ($NODE)"

    docker exec -i "$NODE" psql -U postgres -d shard -q -v ON_ERROR_STOP=1 \
        -c "TRUNCATE orders, order_items, users, products, categories, shard_info;" 2>/dev/null \
    || docker exec -i "$NODE" psql -U postgres -d shard -q -f - < "$(dirname "$0")/../sql/02-shard-schema.sql"

    # Справочники целиком: они нужны каждому шарду для локальных JOIN.
    for t in users categories products; do
        docker exec "$SRC" psql -U postgres -d "$SRC_DB" -Atc "COPY (SELECT * FROM $t) TO STDOUT" \
          | docker exec -i "$NODE" psql -U postgres -d shard -q -c "COPY $t FROM STDIN"
        echo "    справочник $t скопирован"
    done

    # Заказы: только те, чей владелец принадлежит этому шарду.
    docker exec "$SRC" psql -U postgres -d "$SRC_DB" -Atc "
        COPY (
            SELECT o.id, o.user_id, o.total_amount, o.status, o.created_at, o.updated_at
            FROM orders o
            JOIN shardlab.user_assignment a ON a.user_id = o.user_id
            WHERE $( [ "$STRATEGY" = "modulo" ] && echo "a.mod_${SHARDS}" || echo "a.ring_${SHARDS}" ) = $i
        ) TO STDOUT" \
      | docker exec -i "$NODE" psql -U postgres -d shard -q -c "COPY orders FROM STDIN"

    # Позиции заказов едут вслед за своим заказом, с проставленным user_id.
    docker exec "$SRC" psql -U postgres -d "$SRC_DB" -Atc "
        COPY (
            SELECT oi.id, oi.order_id, o.user_id, oi.product_id, oi.quantity, oi.unit_price, oi.total_price
            FROM order_items oi
            JOIN orders o ON o.id = oi.order_id
            JOIN shardlab.user_assignment a ON a.user_id = o.user_id
            WHERE $( [ "$STRATEGY" = "modulo" ] && echo "a.mod_${SHARDS}" || echo "a.ring_${SHARDS}" ) = $i
        ) TO STDOUT" \
      | docker exec -i "$NODE" psql -U postgres -d shard -q -c "COPY order_items FROM STDIN"

    docker exec "$NODE" psql -U postgres -d shard -q -c \
        "INSERT INTO shard_info (shard_id, shard_count, strategy)
         VALUES ($i, $SHARDS, '$STRATEGY')
         ON CONFLICT (shard_id) DO UPDATE SET shard_count = EXCLUDED.shard_count,
                                              strategy = EXCLUDED.strategy,
                                              loaded_at = now();"
    docker exec "$NODE" psql -U postgres -d shard -q -c "ANALYZE;"

    docker exec "$NODE" psql -U postgres -d shard -c \
        "SELECT (SELECT count(*) FROM orders)      AS orders,
                (SELECT count(*) FROM order_items) AS items,
                (SELECT count(*) FROM users)       AS users,
                pg_size_pretty(pg_database_size('shard')) AS size;"
done

echo
echo "=== Итоговое распределение"
for i in $(seq 0 $((SHARDS - 1))); do
    CNT=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc "SELECT count(*) FROM orders;")
    SIZE=$(docker exec "chakchakshop_shard${i}" psql -U postgres -d shard -tAc "SELECT pg_size_pretty(pg_database_size('shard'));")
    printf 'Shard %d -> %10s записей, %s\n' "$i" "$CNT" "$SIZE"
done
