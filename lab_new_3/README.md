# Лабораторная работа №3. Партиционирование PostgreSQL

Разделение больших таблиц, автоматическое создание партиций, контроль
горизонта и alerting. Все планы и цифры ниже получены на живой базе
сервиса ChakChakShop, сырые логи прогонов лежат в [`raw/`](raw).

**Отчёт для защиты:** https://claude.ai/code/artifact/331d1f26-a1f7-43d6-b9e5-3c10b92cf361

---

## Стенд

| | |
|---|---|
| СУБД | PostgreSQL 16.14 в Docker, `shm_size: 1gb` |
| Сервис | ChakChakShop.API, .NET 8, Npgsql + Dapper |
| Боевая таблица | `orders` — 5 000 003 строки, 1067 MB, 25 месяцев данных |
| Учебные таблицы | схема `lab3`: `events` (3 млн), `user_events` (4 млн), `customers` (1.17 млн), `products` (300 тыс.) |
| Дата прогона | 2026-09-11 |

Учебные таблицы вынесены в отдельную схему `lab3` намеренно: в `public`
у сервиса уже есть свои `products` и `orders`, и работать с одноимёнными
объектами в одной схеме нельзя.

### Как воспроизвести

```bash
docker compose up -d postgres
for f in sql/part1-range-date.sql sql/part2-range-numeric.sql sql/part3-list.sql \
         sql/part4-hash.sql sql/part5-index.sql sql/part6-orders-baseline.sql \
         sql/part7-orders-partition.sql sql/part8-orders-after.sql \
         sql/part8b-fair-comparison.sql sql/part9-partition-automation.sql \
         sql/part11-write-cost.sql; do
    docker exec -i chakchakshop_postgres psql -U postgres -d chakchakshop -f - < "$f"
done
```

Автоматизация (части 10–11) живёт в коде сервиса:
`src/ChakChakShop.API/Services/Partitioning/` в репозитории
[cproject](https://github.com/EgorDyach/cproject), копия — в [`jobs/`](jobs).

---

## Часть 1. RANGE PARTITIONING по дате

```sql
CREATE TABLE lab3.events (
    id         BIGINT      NOT NULL,
    user_id    BIGINT      NOT NULL,
    event_type VARCHAR(50) NOT NULL,
    payload    TEXT,
    created_at TIMESTAMP   NOT NULL
) PARTITION BY RANGE (created_at);

CREATE TABLE lab3.events_2026_09_09 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-09') TO ('2026-09-10');
CREATE TABLE lab3.events_2026_09_10 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-10') TO ('2026-09-11');
CREATE TABLE lab3.events_2026_09_11 PARTITION OF lab3.events
    FOR VALUES FROM ('2026-09-11') TO ('2026-09-12');
```

Загрузка трёх миллионов событий, по миллиону на день:

```sql
INSERT INTO lab3.events (id, user_id, event_type, payload, created_at)
SELECT g,
       (floor(random() * 100000) + 1)::bigint,
       (ARRAY['click','view','purchase','signup','logout'])[floor(random() * 5 + 1)::int],
       'payload-' || g,
       '2026-09-09'::timestamp + (random() * 3) * INTERVAL '1 day'
FROM generate_series(1, 3000000) g;
```

```sql
SELECT tableoid::regclass AS partition_name, COUNT(*)
FROM lab3.events GROUP BY tableoid ORDER BY partition_name;
```

```
  partition_name   |  count
-------------------+---------
 events_2026_09_09 | 1000675
 events_2026_09_10 | 1000386
 events_2026_09_11 |  998939
```

Каждая партиция — 74 MB, физически три отдельные таблицы.

### Задание: куда попадёт запись

Проверено вставками, а не рассуждением:

```sql
INSERT INTO lab3.events VALUES (900000001, 1, 'probe', 'q1', '2026-09-10 12:00:00');
INSERT INTO lab3.events VALUES (900000002, 1, 'probe', 'q2', '2026-09-11 00:00:00');
INSERT INTO lab3.events VALUES (900000003, 1, 'probe', 'q3', '2026-09-10 23:59:59.999999');

SELECT id, created_at, tableoid::regclass AS landed_in
FROM lab3.events WHERE event_type = 'probe' ORDER BY id;
```

```
    id     |         created_at         |     landed_in
-----------+----------------------------+-------------------
 900000001 | 2026-09-10 12:00:00        | events_2026_09_10
 900000002 | 2026-09-11 00:00:00        | events_2026_09_11
 900000003 | 2026-09-10 23:59:59.999999 | events_2026_09_10
```

**1. `created_at = '2026-09-10 12:00:00'`** → `events_2026_09_10`. Полдень
десятого числа лежит внутри диапазона `['2026-09-10', '2026-09-11')`.

**2. `created_at = '2026-09-11 00:00:00'`** → `events_2026_09_11`, а не
`events_2026_09_10`. Полночь одиннадцатого — это уже нижняя граница
следующей партиции, а нижняя граница включается.

**3. Запись за 2026-09-12** — вставка падает:

```sql
INSERT INTO lab3.events VALUES (900000004, 1, 'probe', 'q4', '2026-09-12 10:00:00');
```

```
ERROR:  no partition of relation "events" found for row
DETAIL:  Partition key of the failing row contains (created_at) = (2026-09-12 10:00:00).
```

Это и есть та авария, ради предотвращения которой в части 10 пишется job:
данные не «уходят в никуда», приложение получает ошибку на INSERT.

**4. Почему `TO ('2026-09-11')` не включает эту дату.** Диапазон RANGE —
полуинтервал `[FROM, TO)`. Иначе соседние партиции `… TO ('2026-09-11')`
и `FROM ('2026-09-11') …` пересекались бы ровно в одной точке, и
PostgreSQL не смог бы однозначно выбрать, куда положить строку. Полуинтервал
даёт ещё и удобство записи: конец одной партиции дословно совпадает
с началом следующей, без «минус одна микросекунда».

---

## Часть 2. Partition pruning

### Запрос по ключу партиционирования

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events
WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11';
```

```
 Finalize Aggregate  (actual time=38.006..41.513 rows=1 loops=1)
   Buffers: shared hit=5372 read=4109
   ->  Gather
         ->  Partial Aggregate
               ->  Parallel Seq Scan on events_2026_09_10 events
                     Filter: ((created_at >= '2026-09-10 00:00:00') AND (created_at < '2026-09-11 00:00:00'))
 Execution Time: 41.530 ms
```

### Запрос не по ключу

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'click';
```

```
 Finalize Aggregate  (actual time=69.191..73.688 rows=1 loops=1)
   Buffers: shared hit=16146 read=12288
   ->  Parallel Append
         ->  Parallel Seq Scan on events_2026_09_09 events_1
         ->  Parallel Seq Scan on events_2026_09_10 events_2
         ->  Parallel Seq Scan on events_2026_09_11 events_3
 Execution Time: 73.704 ms
```

### Ответы на задание

| Вопрос | Ответ |
|---|---|
| Сколько партиций проверил PostgreSQL | Одну. В плане присутствует только `events_2026_09_10` |
| Какая партиция нужна запросу | `events_2026_09_10` — диапазон условия совпадает с её границами |
| Удалось ли исключить остальные | Да, на этапе планирования |
| Где в плане видно pruning | Именно в отсутствии узлов. Партиция, которую отсекли, не появляется в плане вообще — нет ни `Append`, ни строки с её именем |

Численное подтверждение: 9 481 страница против 28 434, ровно втрое —
столько же, сколько партиций. Время 41.5 мс против 73.7 мс.

### Почему второй запрос обращается ко всем партициям

`event_type` не является ключом партиционирования. Планировщик знает
границы партиций только по `created_at`; про распределение `event_type`
внутри партиций ему ничего не известно, и исключить партицию, не заглянув
в неё, он не имеет права — любая может содержать `'click'`. Отсюда узел
`Parallel Append` с полным списком партиций.

**Правило: pruning срабатывает только тогда, когда ключ партиционирования
присутствует в `WHERE`.** Без него партиционирование не помогает, а мешает —
к цене чтения добавляется цена обхода нескольких таблиц.

### Runtime pruning

Отдельно проверено, что pruning работает и для параметров, значение
которых планировщику не известно заранее:

```sql
PREPARE p_events(timestamp, timestamp) AS
SELECT COUNT(*) FROM lab3.events WHERE created_at >= $1 AND created_at < $2;
EXPLAIN (ANALYZE, BUFFERS) EXECUTE p_events('2026-09-10', '2026-09-11');
```

План снова содержит единственную партицию, время 42.5 мс. Это важно
для приложения: запросы идут через параметризованные команды Npgsql,
а не подстановкой констант в текст.

---

## Часть 3. RANGE PARTITIONING по числовому значению

```sql
CREATE TABLE lab3.products (
    id    BIGINT  NOT NULL,
    name  TEXT    NOT NULL,
    price NUMERIC NOT NULL
) PARTITION BY RANGE (price);

CREATE TABLE lab3.products_cheap     PARTITION OF lab3.products FOR VALUES FROM (0)    TO (100);
CREATE TABLE lab3.products_medium    PARTITION OF lab3.products FOR VALUES FROM (100)  TO (1000);
CREATE TABLE lab3.products_expensive PARTITION OF lab3.products FOR VALUES FROM (1000) TO (MAXVALUE);
```

```
 id |            name            |  price  |     landed_in
----+----------------------------+---------+--------------------
  1 | Чак-чак мини 100 г         |   99.99 | products_cheap
  2 | Чак-чак классический 500 г |  100.00 | products_medium
  3 | Чак-чак подарочный 1 кг    |  999.99 | products_medium
  4 | Корпоративный набор        | 1000.00 | products_expensive
  5 | Свадебный чак-чак 10 кг    | 7500.00 | products_expensive
  6 | Пробник 50 г               |    0.00 | products_cheap
```

Граница ведёт себя точно так же, как с датами: `99.99` — дешёвый,
ровно `100.00` — уже средний.

### Задание

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE price >= 100 AND price < 500;
```

```
 Seq Scan on products_medium products  (actual time=0.002..3.222 rows=24069 loops=1)
   Filter: ((price >= '100'::numeric) AND (price < '500'::numeric))
   Rows Removed by Filter: 30037
   Buffers: shared hit=398
 Execution Time: 3.667 ms
```

**PostgreSQL просматривает одну партицию — `products_medium`.** Интервал
`[100, 500)` целиком вложен в `[100, 1000)`. Партиция `cheap` не может
содержать цену ≥ 100 по определению своих границ, `expensive` — цену < 500.

Контрольный опыт: диапазон, пересекающий границу, читает две партиции:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE price >= 90 AND price < 500;
```

```
 Append  (actual time=0.006..5.334 rows=24792 loops=1)
   ->  Seq Scan on products_cheap products_1   (rows=602)
   ->  Seq Scan on products_medium products_2  (rows=24069)
 Execution Time: 4.830 ms
```

А запрос без ключа партиционирования читает все три (6.611 мс против 3.667):

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.products WHERE name = 'product-12345';
```

Отдельно стоит заметить перекос: `cheap` — 5 942 строки, `medium` — 54 106,
`expensive` — 239 859. Ключ по цене при равномерном распределении цен
даёт партиции, различающиеся в сорок раз. Для RANGE по деньгам это
типично, и границы приходится подбирать по фактическому распределению,
а не «по красивым числам».

---

## Часть 4. LIST PARTITIONING

```sql
CREATE TABLE lab3.customers (
    id            BIGINT      NOT NULL,
    name          TEXT        NOT NULL,
    customer_type VARCHAR(30) NOT NULL
) PARTITION BY LIST (customer_type);

CREATE TABLE lab3.customers_b2c        PARTITION OF lab3.customers FOR VALUES IN ('B2C');
CREATE TABLE lab3.customers_b2b        PARTITION OF lab3.customers FOR VALUES IN ('B2B');
CREATE TABLE lab3.customers_enterprise PARTITION OF lab3.customers FOR VALUES IN ('Enterprise');
```

Данные загружены с реалистичным перекосом: 1 000 000 / 150 000 / 20 000.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.customers WHERE customer_type = 'B2B';
```

```
 Seq Scan on customers_b2b customers  (actual time=0.004..7.493 rows=150000 loops=1)
   Filter: ((customer_type)::text = 'B2B'::text)
   Buffers: shared hit=1103
 Execution Time: 10.330 ms
```

### Ответы

**Какая партиция используется** — `customers_b2b`, единственная в плане.

**Почему PostgreSQL не обращается к другим.** Границы LIST — это явный
список значений, записанный в каталоге. `customers_b2c` объявлена как
`FOR VALUES IN ('B2C')`, значит строки с `customer_type = 'B2B'` в ней
физически не могут находиться — СУБД это гарантирует на вставке. Проверять
нечего.

**Чем сценарий отличается от RANGE.** У RANGE отсечение — это сравнение
интервалов: условие может накрыть половину партиций, и тогда прочитаются
все они. У LIST отсечение — проверка принадлежности множеству, и запрос
по равенству всегда попадает ровно в одну партицию. Обратная сторона: RANGE
умеет работать с неограниченным потоком новых значений (новый месяц —
новая партиция), а LIST требует, чтобы список значений был известен заранее.
Что делать с неизвестным значением — следующая часть.

`IN (...)` тоже отсекает — читаются ровно две партиции из трёх:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT customer_type, count(*) FROM lab3.customers
WHERE customer_type IN ('B2B','Enterprise') GROUP BY customer_type;
```

---

## Часть 5. LIST PARTITIONING: неизвестное значение

```sql
INSERT INTO lab3.customers VALUES (100, 'Test User', 'VIP');
```

```
ERROR:  no partition of relation "customers" found for row
DETAIL:  Partition key of the failing row contains (customer_type) = (VIP).
```

```sql
CREATE TABLE lab3.customers_default PARTITION OF lab3.customers DEFAULT;
INSERT INTO lab3.customers VALUES (100, 'Test User', 'VIP');
```

```
 id  |   name    | customer_type |     landed_in
-----+-----------+---------------+-------------------
 100 | Test User | VIP           | customers_default
```

### Задание

**1. Зачем нужна DEFAULT partition.** Чтобы появление значения, которого
не было в проекте, не превращалось в отказ записи. Без DEFAULT новый тип
клиента роняет INSERT, то есть ошибка в справочнике становится инцидентом
доступности.

**2. Чем она полезна.** DEFAULT — это страховка, которая переводит
жёсткий отказ в мягкую деградацию: данные сохранены, их видно, и разбор
можно отложить до рабочего времени. Мониторинг размера DEFAULT-партиции
заодно работает сигналом «в системе появился тип, которого мы не ждали».

**3. Какие проблемы возникают, если складывать в DEFAULT постоянно.**
Три, и все проверены отдельными опытами.

*Проблема первая — pruning вырождается.* Пока значение не перечислено ни
в одной партиции, запрос по нему обязан читать DEFAULT. Хуже того, запрос
по значению, которое вообще нигде не объявлено, всегда идёт в DEFAULT —
а она растёт.

*Проблема вторая — DEFAULT становится «большой таблицей внутри
партиционированной».* После загрузки 500 000 VIP-клиентов расклад стал таким:

```
    partition_name    |  count
----------------------+---------
 customers_b2c        | 1000000
 customers_b2b        |  150000
 customers_enterprise |   20000
 customers_default    |  500001
```

Второй по величине «раздел» — свалка. Партиционирование в этой части
таблицы перестало работать.

*Проблема третья, самая неприятная — DEFAULT мешает всё исправить.*
Попытка «узаконить» тип отдельной партицией:

```sql
CREATE TABLE lab3.customers_vip PARTITION OF lab3.customers FOR VALUES IN ('VIP');
```

```
ERROR:  updated partition constraint for default partition "customers_default"
        would be violated by some row
```

PostgreSQL обязан гарантировать, что в DEFAULT не осталось строк, которые
теперь должны лежать в новой партиции. Пока они там есть, команда падает.
Чинится это переносом данных под `ACCESS EXCLUSIVE` — то есть с простоем:

```sql
BEGIN;
ALTER TABLE lab3.customers DETACH PARTITION lab3.customers_default;
CREATE TABLE lab3.customers_vip (LIKE lab3.customers INCLUDING DEFAULTS);
INSERT INTO lab3.customers_vip SELECT * FROM lab3.customers_default WHERE customer_type = 'VIP';
DELETE FROM lab3.customers_default WHERE customer_type = 'VIP';
ALTER TABLE lab3.customers ATTACH PARTITION lab3.customers_vip FOR VALUES IN ('VIP');
ALTER TABLE lab3.customers ATTACH PARTITION lab3.customers_default DEFAULT;
COMMIT;
```

Перенос 500 001 строки занял 0.4 с на учебном объёме; на реальных
миллиардах это окно обслуживания. После переноса запрос по VIP снова
читает одну партицию.

**Вывод: DEFAULT — приёмник для аварийных случаев, а не место хранения.
Она должна оставаться пустой, и её непустота — повод для алерта.**

---

## Часть 6. HASH PARTITIONING

```sql
CREATE TABLE lab3.user_events (
    id         BIGINT      NOT NULL,
    user_id    BIGINT      NOT NULL,
    event_type VARCHAR(50),
    created_at TIMESTAMP   NOT NULL
) PARTITION BY HASH (user_id);

CREATE TABLE lab3.user_events_0 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 0);
CREATE TABLE lab3.user_events_1 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 1);
CREATE TABLE lab3.user_events_2 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 2);
CREATE TABLE lab3.user_events_3 PARTITION OF lab3.user_events FOR VALUES WITH (MODULUS 4, REMAINDER 3);
```

4 000 000 событий на 200 000 пользователей.

```sql
SELECT tableoid::regclass AS partition_name, COUNT(*),
       round(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 3) AS pct
FROM lab3.user_events GROUP BY tableoid ORDER BY partition_name;
```

```
 partition_name |  count  |  pct
----------------+---------+--------
 user_events_0  |  996428 | 24.911
 user_events_1  | 1004794 | 25.120
 user_events_2  |  997361 | 24.934
 user_events_3  | 1001417 | 25.035
```

### Ответы

**1. Насколько равномерно распределились данные.** Отклонение от идеальных
25 % не превышает 0.12 процентного пункта, размер всех четырёх партиций —
по 60 MB. Это не случайность: `satisfies_hash_partition` использует
внутреннюю хеш-функцию PostgreSQL, у которой хорошее лавинное свойство,
поэтому даже последовательные `user_id` размазываются ровно.

**2. Почему HASH может быть полезен.** Когда у данных нет естественного
интервала или категории, а разделить их надо. Типичные поводы: снять
блокировку с «горячего» конца таблицы (при RANGE по времени вся запись
идёт в одну последнюю партицию — она и становится узким местом),
уменьшить каждый локальный индекс в N раз, разложить партиции по разным
табличным пространствам и дискам.

**3. Чем HASH отличается от RANGE.** RANGE сохраняет порядок: соседние
значения ключа лежат рядом, поэтому отсекать можно по интервалу. HASH
порядок уничтожает намеренно — ради равномерности. Расплата в том, что
отсечение работает только на равенстве. Проверено:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM lab3.user_events WHERE user_id = 12345;
-- Parallel Seq Scan on user_events_0 — одна партиция, 28.301 ms

EXPLAIN (ANALYZE, BUFFERS) SELECT count(*) FROM lab3.user_events WHERE user_id BETWEEN 1 AND 1000;
-- Parallel Append по всем четырём партициям, 67.522 ms
```

Диапазон `user_id BETWEEN 1 AND 1000` отсечь нельзя: хеши единицы и тысячи
не связаны ничем, тысяча подряд идущих значений равномерно размазана по
всем партициям.

**4. Почему HASH плохо подходит для «удалить данные старше 3 лет».**
Потому что старые данные размазаны по всем партициям ровно так же
равномерно, как и свежие:

```
 partition_name | older_than_3y |  total
----------------+---------------+---------
 user_events_0  |        248178 |  996428
 user_events_1  |        250066 | 1004794
 user_events_2  |        248522 |  997361
 user_events_3  |        249300 | 1001417
```

Ни одну партицию нельзя выбросить целиком — придётся выполнять обычный
`DELETE` по всем четырём:

```sql
EXPLAIN (ANALYZE, BUFFERS)
DELETE FROM lab3.user_events WHERE created_at < NOW() - INTERVAL '3 years';
```

```
 Delete on user_events  (actual time=868.423..868.424 rows=0 loops=1)
   Delete on user_events_0 … user_events_3
   Buffers: shared hit=999732 read=27137 dirtied=27425 written=26244
 Execution Time: 872.227 ms
```

872 мс, почти миллион удалённых строк, 27 425 «грязных» страниц — и после
этого ещё нужен `VACUUM`, потому что место `DELETE` не освобождает.
На RANGE-партиционировании та же задача решается командой `DROP TABLE`
за единицы миллисекунд (часть 9, опыт 9.7: миллион строк и 121 MB
исчезли за 12.8 мс).

---

## Часть 7. Выбор стратегии партиционирования

| Сценарий | Стратегия | Обоснование |
|---|---|---|
| **A.** Миллионы событий в день, через 3 года нужно быстро удалять старое | **RANGE по дате** (по дню или месяцу) | Удаление превращается в `DROP TABLE` целой партиции — мгновенно, без `DELETE`, без раздувания и без `VACUUM`. Ровно этот выигрыш измерен в части 9: 12.8 мс против сотен миллисекунд и последующей уборки |
| **B.** Три типа пользователей, запросы фильтруют по этому признаку | **LIST по `customer_type`** | Множество значений конечно и известно заранее, а запрос по равенству попадает ровно в одну партицию. RANGE здесь не нужен: у типов нет порядка, по которому имеет смысл строить интервалы |
| **C.** Равномерно разложить данные по нескольким физическим разделам по `user_id` | **HASH по `user_id`** | Ровно та задача, для которой HASH и придуман: ни интервала, ни категории нет, зато нужна равномерность. В опыте отклонение вышло 0.12 п. п. |
| **D.** Аналитика заказов почти всегда идёт по `created_at BETWEEN …` | **RANGE по `created_at`** (по месяцу) | Ключ присутствует в `WHERE` подавляющего большинства запросов, значит pruning будет срабатывать. Это и реализовано в части 12 на таблице `orders` |
| **E.** Платежи делятся по странам EE, LV, LT, FI, SE | **LIST по коду страны** | Список стран конечен и меняется раз в несколько лет. Дополнительный довод: требования к хранению персональных данных обычно заданы по странам, а отдельная партиция — это ещё и отдельный файл, который можно вынести в своё табличное пространство. Обязательна DEFAULT-партиция: новая страна не должна ронять приём платежей |

---

## Часть 8. Партиционирование и индексы

Базовая линия — запрос без индексов, только с pruning:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.events
WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'
  AND user_id = 12345;
```

```
 Gather  (actual time=0.760..97.676 rows=10 loops=1)
   ->  Parallel Seq Scan on events_2026_09_10 events
         Rows Removed by Filter: 333459
 Execution Time: 97.767 ms
```

Партиция выбрана правильно, но внутри неё всё равно перебирается миллион
строк ради десяти.

```sql
CREATE INDEX idx_events_user_id ON lab3.events (user_id);
```

Индекс создаётся на родителе, а появляется в каждой партиции:

```
          index_name           | relkind |     on_table      |  size
-------------------------------+---------+-------------------+---------
 events_2026_09_09_user_id_idx | i       | events_2026_09_09 | 9088 kB
 events_2026_09_10_user_id_idx | i       | events_2026_09_10 | 9088 kB
 events_2026_09_11_user_id_idx | i       | events_2026_09_11 | 9080 kB
 idx_events_user_id            | I       | events            | 0 bytes
```

Строка с `relkind = 'I'` и нулевым размером — это «зонтичный» индекс на
родительской таблице. Он не хранит ничего: данных в родителе нет, есть
только описание. Реальные записи лежат в трёх локальных индексах.

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM lab3.events
WHERE created_at >= '2026-09-10' AND created_at < '2026-09-11'
  AND user_id = 12345;
```

```
 Bitmap Heap Scan on events_2026_09_10 events  (actual time=0.055..0.134 rows=10 loops=1)
   Recheck Cond: (user_id = 12345)
   Filter: ((created_at >= '2026-09-10 00:00:00') AND (created_at < '2026-09-11 00:00:00'))
   Heap Blocks: exact=10
   Buffers: shared hit=3 read=13
   ->  Bitmap Index Scan on events_2026_09_10_user_id_idx
         Index Cond: (user_id = 12345)
 Execution Time: 0.198 ms
```

### Ответы

**1. Какие партиции отфильтрованы через pruning.** Две из трёх:
`events_2026_09_09` и `events_2026_09_11`. В плане осталась одна.

**2. Используется ли индекс.** Да — `Bitmap Index Scan on
events_2026_09_10_user_id_idx`. Планировщик выбрал Bitmap, а не обычный
Index Scan, потому что десять найденных строк лежат в десяти разных
страницах (`Heap Blocks: exact=10`): дешевле собрать битовую карту
страниц и прочитать их по порядку, чем десять раз прыгать по диску.

**3. На каком уровне существует индекс.** Физически — на уровне партиции.
Логически — на уровне родительской таблицы, и это важно: новая партиция
получает локальный индекс автоматически, а `DROP TABLE` партиции уносит
её индекс с собой, не трогая остальные.

**4. Почему комбинация partitioning + index эффективнее каждого механизма
по отдельности.** Они решают разные половины задачи.

| | Что делает | Что не умеет |
|---|---|---|
| Партиционирование | Отбрасывает данные **пачками**, не читая их вообще | Найти конкретную строку внутри пачки |
| Индекс | Находит конкретную строку внутри таблицы | Отбросить таблицу целиком |

Цифры по шагам: 97.767 мс (только pruning) → **0.198 мс** (pruning + индекс),
**в 494 раза**. При этом индекс, работающий без pruning, читает все три
локальных индекса:

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM lab3.events WHERE user_id = 12345;
-- Append из трёх Bitmap Heap Scan, 0.911 ms — впятеро медленнее
```

Отдельный практический бонус: индекс на маленькой партиции ниже по высоте
дерева и целиком помещается в память, тогда как один индекс на всю таблицу
рано или поздно перестаёт в неё влезать — с этого и начинается вся тема
партиционирования.

---

## Часть 9. Когда партиционирование не помогает

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT COUNT(*) FROM lab3.events WHERE event_type = 'click';
```

| Шаг | План | Время | Страниц |
|---|---|---|---|
| Только партиционирование | `Parallel Append` по 3 партициям, `Parallel Seq Scan` | 72.923 мс | 28 434 |
| `CREATE INDEX idx_events_event_type ON lab3.events (event_type)` | `Parallel Append` по 3 партициям, `Parallel Index Only Scan` | **33.087 мс** | 522 |
| То же с покрывающим `INCLUDE (created_at)` | `Parallel Index Only Scan` | 25.145 мс | 522 |

```sql
CREATE INDEX idx_events_event_type ON lab3.events (event_type);
```

### Почему partitioning сам по себе не решил проблему этого запроса

Потому что запрос спрашивает не про время, а про тип события. Ключ
партиционирования — `created_at`, и в условии его нет. Планировщику
нечем отсечь партиции: `'click'` может встречаться в любой из них, и
встречается — 600 487 раз из трёх миллионов, примерно поровну по дням.
Партиционирование по дате в этом запросе не даёт ничего, кроме накладных
расходов на обход трёх таблиц вместо одной.

Индекс ускорил в 2.2 раза, и это вся возможная выгода: `'click'` — это
20 % таблицы, низкая селективность. Индекс здесь работает не как «найти
нужное», а как «прочитать тот же объём данных, но из более компактной
структуры»: 522 страницы индекса вместо 28 434 страниц кучи. `Heap
Fetches: 0` — до самой таблицы дело вообще не дошло, сработал Index Only
Scan.

Для сравнения — тот же индекс на селективном значении. Добавлено 300
событий типа `'refund'` (0.01 % таблицы):

```sql
EXPLAIN (ANALYZE, BUFFERS) SELECT COUNT(*) FROM lab3.events WHERE event_type = 'refund';
-- Index Only Scan, 0.299 ms
```

**0.299 мс против 25 мс на том же индексе и той же таблице.** Разница —
только в селективности условия.

### Вывод: партиционирование отвечает на одну проблему, а индекс — на другую

| | Партиционирование | Индекс |
|---|---|---|
| Отвечает на вопрос | «какие данные можно **не читать вообще**» | «где внутри данных лежит нужная строка» |
| Единица работы | физическая таблица | строка |
| Работает, когда | ключ партиционирования есть в `WHERE` | условие селективно |
| Что даёт при промахе | замедление: обход N таблиц | замедление: лишний объём и лишняя работа на записи |
| Чего не умеет | найти строку | мгновенно удалить старые данные |

Последний пункт измерен отдельно. Создана партиция за 2026-09-08,
в неё загружен миллион строк (121 MB), после чего:

```sql
DROP TABLE lab3.events_2026_09_08;   -- 12.835 ms
```

Миллион строк и 121 MB исчезли за 12.8 мс, без `VACUUM` и без раздувания.
Никаким индексом это не заменяется.

Ещё одна цифра, которую стоит держать в голове: после трёх индексов
на `lab3.events` данные занимают 222 MB, а индексы — 142 MB, то есть
64 % от объёма самих данных. Каждый из них замедляет `INSERT`.

---

## Часть 10. Автоматическое создание партиций

Партиции по дням заканчиваются сами по себе: сегодня 2026-09-11,
последняя существующая партиция — за 11-е, и завтра сервис начнёт падать
на `INSERT`. Требование: партиции всегда должны существовать минимум
на три дня вперёд.

Реализация — фоновая служба `CreatePartitionsJob` в самом сервисе
([`jobs/CreatePartitionsJob.cs`](jobs/CreatePartitionsJob.cs)), а не
отдельный скрипт в cron: так у job'а те же логи, та же конфигурация
и тот же цикл деплоя, что у остального кода.

### Конфигурация

Таблица, шаг и горизонт заданы настройками, а не зашиты в код —
одна и та же job обслуживает и дневные `events`, и месячные `orders`:

```json
"Partitioning": {
  "Enabled": true,
  "CreateJobTimeOfDay": "01:00:00",
  "HealthCheckInterval": "00:05:00",
  "RenotifyAfter": "06:00:00",
  "Tables": [
    { "Schema": "lab3",   "Table": "events",             "Interval": "Daily",   "NamePrefix": "events_",   "HorizonPeriods": 3 },
    { "Schema": "public", "Table": "orders_partitioned", "Interval": "Monthly", "NamePrefix": "orders_p_", "HorizonPeriods": 3 }
  ]
}
```

### Ядро

```csharp
foreach (var periodStart in table.RequiredPeriods(DateTime.UtcNow))
{
    var name = table.PartitionName(periodStart);
    if (existing.Contains(name)) continue;      // уже есть — не трогаем

    await CreatePartitionAsync(connection, table, name, periodStart, table.Next(periodStart), ct);
}
```

```csharp
var sql = $@"
    CREATE TABLE IF NOT EXISTS {Quote(table.Schema)}.{Quote(partitionName)}
    PARTITION OF {Quote(table.Schema)}.{Quote(table.Table)}
    FOR VALUES FROM ('{from:yyyy-MM-dd HH:mm:ss}') TO ('{to:yyyy-MM-dd HH:mm:ss}')";
```

Требования задания закрыты так:

| Требование | Как выполнено |
|---|---|
| Создавать недостающие партиции | Список требуемых периодов считается от текущей даты: `RequiredPeriods` возвращает текущий период и `HorizonPeriods` следующих |
| Не создавать уже существующие | Существующие читаются из `pg_inherits` одним запросом и сравниваются по имени |
| Быть безопасной при повторном запуске | Двойная защита: проверка по списку **и** `CREATE TABLE IF NOT EXISTS`. Сверх того — `pg_try_advisory_lock`, поэтому второй экземпляр сервиса не полезет создавать то же самое параллельно |
| Логировать результат | Отчёт печатается одним блоком в формате из задания |

Существующие партиции берутся прямо из каталога:

```sql
SELECT c.relname, pg_get_expr(c.relpartbound, c.oid), pg_total_relation_size(c.oid)
FROM pg_class c
JOIN pg_inherits i  ON i.inhrelid = c.oid
JOIN pg_class p     ON p.oid = i.inhparent
JOIN pg_namespace n ON n.oid = p.relnamespace
WHERE n.nspname = @Schema AND p.relname = @Table
ORDER BY c.relname;
```

### Результат работы

Запуск на состоянии «есть партиции по 11 сентября включительно»
([`raw/part10-create-job.log`](raw/part10-create-job.log)):

```
[08:04:57 INF] Partition job started.

Existing partitions: 28
Required partitions: 8
Missing partitions: 6

Creating:
events_2026_09_12  [2026-09-12 .. 2026-09-13)
events_2026_09_13  [2026-09-13 .. 2026-09-14)
events_2026_09_14  [2026-09-14 .. 2026-09-15)
orders_p_2026_10  [2026-10-01 .. 2026-11-01)
orders_p_2026_11  [2026-11-01 .. 2026-12-01)
orders_p_2026_12  [2026-12-01 .. 2027-01-01)

Partition created successfully.

Partition job finished in 103 ms.
```

Повторный запуск (`POST /api/partitions/ensure`) находит `missing: 0`
и не делает ничего — идемпотентность проверена, а не заявлена.

---

## Часть 11. Production-сценарий: ночная job сломалась

Логировать ошибку недостаточно: лог никто не читает в три часа ночи.
Нужна проверка, которая обнаружит проблему **до** того, как приложение
начнёт падать на `INSERT`, и уведомление, которое дойдёт до человека.

### PartitionHealthCheck

```csharp
var expected = table.RequiredPeriods(now).Select(table.PartitionName).ToList();
var missing  = expected.Where(name => !existing.Contains(name)).ToList();

tables.Add(new TablePartitionHealth(table.QualifiedName, table.HorizonPeriods, expected, missing));
```

Статус таблицы — `CRITICAL`, если не хватает хотя бы одной партиции
из горизонта. Проверка доступна и как фоновая служба (раз в 5 минут),
и как HTTP-ручка:

```bash
curl -H "X-API-Key: …" http://localhost:8090/api/partitions/health
```

```json
{
  "status": "OK",
  "checkedAt": "2026-09-11 08:05:45",
  "tables": [
    { "table": "lab3.events", "status": "OK", "horizon": 3,
      "expected": ["events_2026_09_11","events_2026_09_12","events_2026_09_13","events_2026_09_14"],
      "missing": [] },
    { "table": "public.orders_partitioned", "status": "OK", "horizon": 3,
      "expected": ["orders_p_2026_09","orders_p_2026_10","orders_p_2026_11","orders_p_2026_12"],
      "missing": [] }
  ]
}
```

При `CRITICAL` ручка возвращает HTTP 503 — чтобы её можно было завести
во внешний мониторинг как обычную health-проверку.

### Канал уведомлений

Уведомления уходят одновременно во все настроенные каналы:

| Канал | Когда используется |
|---|---|
| `LogAlertNotifier` | всегда — alert обязан остаться в логе, даже если внешний канал недоступен |
| `WebhookAlertNotifier` | VK, MAX, Telegram, Slack: POST с JSON-телом, имя текстового поля и служебные поля (`chat_id`, `peer_id`, `access_token`) задаются конфигурацией |
| `EmailAlertNotifier` | SMTP, если заполнена секция `Alerts:Email` |

Для демонстрации поднят локальный приёмник webhook'ов
[`tools/alert-sink.py`](tools/alert-sink.py) — он печатает пришедшее
сообщение в `docker logs`. Наружу при этом ничего не отправляется:

```yaml
# docker-compose.override.yml
api:
  environment:
    - Partitioning__Alerts__WebhookUrl=http://alert_sink:8099/hook
```

### Проверка того, что alert действительно работает

Сценарий из задания выполнен целиком
([`raw/part11-auto-detection.log`](raw/part11-auto-detection.log)).

**1. Искусственная авария.** Удаляется одна будущая партиция:

```bash
curl -X DELETE -H "X-API-Key: …" \
     http://localhost:8090/api/partitions/lab3.events/events_2026_09_14
```

```json
{ "dropped": "events_2026_09_14" }
```

Ручка намеренно ограничена: удалять можно только партиции **будущих**
периодов. Попытка удалить текущую или историческую отвергается —
инструмент для учебной аварии не должен уметь уносить данные.

**2. Проверку никто не вызывал — она нашла проблему сама.** Через 27
секунд после удаления:

```
[08:06:12 FTL] PARTITION ALERT 🚨 Partition alert: lab3.events
🚨 Partition alert

Table: lab3.events
Missing partitions:
events_2026_09_14

Expected horizon: 3 days

Checked at:
2026-09-11 08:06:12
```

**3. Уведомление доставлено** — лог приёмника:

```
===== ALERT DELIVERED 2026-09-11 08:06:12 =====
🚨 Partition alert

Table: lab3.events
Missing partitions:
events_2026_09_14

Expected horizon: 3 days

Checked at:
2026-09-11 08:06:12
========================================
```

### Подавление повторов и recovery

Дополнительное задание: система не должна слать один и тот же alert
бесконечно, но обязана сообщить о восстановлении.

Состояние хранится в БД, а не в памяти процесса — перезапуск сервиса
не должен приводить к повторной рассылке, а несколько экземпляров должны
видеть общую картину:

```sql
CREATE TABLE partition_alert_state (
    alert_key        varchar(200) PRIMARY KEY,
    status           varchar(20)  NOT NULL,
    details          text,
    first_seen_at    timestamptz  NOT NULL,
    last_notified_at timestamptz,
    notify_count     integer      NOT NULL DEFAULT 0,
    updated_at       timestamptz  NOT NULL
);
```

Логика: уведомление уходит **на смену состояния**, а не на каждую
проверку. Повторное напоминание — только после `RenotifyAfter` (6 часов),
если проблема так и не решена.

```csharp
var isNewProblem   = state is null || state.Status != nameof(PartitionHealthStatus.Critical);
var quietPeriodOver = state?.LastNotifiedAt is not null &&
                      now - state.LastNotifiedAt.Value >= _options.RenotifyAfter;

if (isNewProblem || quietPeriodOver) { /* шлём alert */ }
else                                 { /* только пишем в лог */ }
```

Полный жизненный цикл ([`raw/part11-alert-lifecycle.log`](raw/part11-alert-lifecycle.log)):

| Время | Событие | Действие системы |
|---|---|---|
| 08:05:45 | партиция удалена | — |
| 08:06:12 | фоновая проверка: `CRITICAL` | **alert отправлен** |
| 08:08:04 | проверка вручную: `CRITICAL` | `alert suppressed` |
| 08:08:04 | ещё раз: `CRITICAL` | `alert suppressed` |
| 08:08:04 | `POST /ensure` → создана `events_2026_09_14` | — |
| 08:08:04 | проверка: `OK` | **recovery отправлен** |

```
              alert_key               |  status  |      details      | first_seen | last_notified | notify_count
--------------------------------------+----------+-------------------+------------+---------------+--------------
 partitions:lab3.events               | Critical | events_2026_09_14 | 08:06:12   | 08:06:12      |            1
 partitions:public.orders_partitioned | Ok       |                   | 08:08:04   | 08:05:12      |            0
```

Итог в канале — ровно два сообщения на инцидент, а не бесконечная лента:

```
===== ALERT DELIVERED 2026-09-11 08:08:04 =====
🟢 Partition check OK

Table: lab3.events

All required partitions exist.
Downtime: 1.9 min

Checked at:
2026-09-11 08:08:04
========================================
```

Время простоя считается от `first_seen_at` — именно для этого поле
и хранится отдельно от `last_notified_at`.

### Восстановление

`POST /api/partitions/ensure` — тот же код, что у ночной job'а:

```json
{ "existing": 33, "required": 8, "missing": 1,
  "created": ["events_2026_09_14"], "errors": [], "elapsedMs": 12.7487 }
```

Повторная проверка возвращает `OK`, `notify_count` сбрасывается в ноль,
и следующая авария снова будет считаться новой.

### Незапланированный инцидент: авария, которую никто не подстраивал

Через сутки после сдачи работы стенд сломался сам — и это оказалось
лучшим доказательством из всех, что есть в отчёте
([`raw/part11-real-incident.log`](raw/part11-real-incident.log)).

В полночь сутки сменились на 12 сентября. Горизонт в три дня требует
партиций по 15-е включительно, а последняя существующая была за 14-е.
Ночная job в 01:00 её не создала. Через четыре минуты после смены суток
проверка сообщила о проблеме:

```
[00:04:48 FTL] PARTITION ALERT 🚨 Partition alert: lab3.events

Table: lab3.events
Missing partitions:
events_2026_09_15

Expected horizon: 3 days
```

Дальше система вела себя ровно так, как задумано: пять проверок подряд
дали `alert suppressed`, а в 06:28:41 — через положенные шесть часов
`RenotifyAfter` — ушло повторное напоминание. Два сообщения за десять
часов вместо сотни.

**Почему не отработала job.** Расписание держалось на одном длинном
`Task.Delay` до часа ночи:

```csharp
var delay = TimeUntilNextRun(DateTime.UtcNow);   // 16:55:02
await Task.Delay(delay, stoppingToken);
```

Ноутбук ночью уснул, вместе с ним встала виртуальная машина Docker, и
монотонный таймер внутри контейнера замер. Побочное свидетельство видно
в логе: проверка, настроенная на интервал в одну минуту, отрабатывала с
разрывами в 27, 78, 44 и 50 минут. Единственный запланированный запуск
job'а не состоялся вообще — в логе за сутки есть ровно одна строка
`Partition job started`, и та от старта сервиса.

**Исправление** — расписание на часах вместо длинного ожидания:

```csharp
var nextRun = NextRunAfter(DateTime.UtcNow);
while (!stoppingToken.IsCancellationRequested)
{
    await Task.Delay(TickInterval, stoppingToken);   // одна минута
    if (DateTime.UtcNow < nextRun) continue;

    await RunOnceAsync(stoppingToken);
    nextRun = NextRunAfter(DateTime.UtcNow);
}
```

Короткий тик переживает засыпание хоста, а сравнение с настенными часами
навёрстывает пропущенный запуск при первом же пробуждении. После
пересборки job немедленно доделала то, что должна была сделать ночью:

```
[10:53:23 INF] Partition job started.

Existing partitions: 34
Required partitions: 8
Missing partitions: 1

Creating:
events_2026_09_15  [2026-09-15 .. 2026-09-16)

Partition created successfully.

Partition job finished in 66 ms.

[10:53:23 INF] Next partition job run at 2026-09-13 01:00:00Z
```

И следом — recovery с честным временем простоя:

```
🟢 Partition check OK

Table: lab3.events

All required partitions exist.
Downtime: 648.8 min
```

**Вывод, который стоит всей части 11.** Проверка не дублирует job — она
страхует её. Если бы `PartitionHealthCheck` не существовал, о пропаже
узнали бы только 15 сентября, когда `INSERT` начал бы падать в продакшене.
Горизонт в три дня превратил отказ сервиса в десять часов спокойного
ожидания. Ровно ради этого часть 11 и написана — и здесь она сработала
на настоящей аварии, а не на подстроенной.

---

## Часть 12. Партиционирование собственной базы данных

### Шаги 1–4: выбор и обоснование

**Шаг 1. Таблица — `orders`.** В базе сервиса это единственная таблица,
которая растёт неограниченно: 5 000 003 строки, 1067 MB, 25 месяцев
истории. Для сравнения, `products` — 7 строк, `categories` — 3,
`users` — 50 003. `order_items` растёт вместе с `orders`, но она
производная: её партиционирование имеет смысл только вслед за
родительской таблицей и в эту работу не входит.

**Шаг 2. Ключ — `created_at`.** Три довода, и все проверяемые.

*Довод первый — ключ действительно есть в запросах.* Аналитика сервиса
фильтрует заказы по периоду, список заказов сортирует по дате,
витрина `orders_daily_stats` из прошлой работы агрегирует по дню.
Ключ, которого нет в `WHERE`, бесполезен — это показала часть 9.

*Довод второй — у заказов выраженный жизненный цикл.* Заказ активно
читают первые недели, потом он превращается в историю. Это классика
time-series-данных, для которой RANGE по дате и создавался.

*Довод третий — `created_at` неизменен.* Ключ партиционирования нельзя
менять «на лету»: `UPDATE`, меняющий партицию, — это физическое
перемещение строки. Дата создания заказа не меняется никогда,
в отличие от `status`, который был бы вторым кандидатом.

Почему **не** `status`: значений мало, распределение перекошено, а главное —
статус меняется в жизни заказа, то есть каждая смена статуса приводила бы
к переносу строки между партициями.
Почему **не** `user_id` (HASH): равномерно — да, но тогда пропадает
главная выгода, мгновенное удаление истории, и не работает ни один
запрос по периоду.

**Шаг 3. Стратегия — RANGE по месяцу.** Не по дню: при дневном шаге
за 25 месяцев накопилось бы 760 партиций, и планировщик тратил бы
заметное время просто на разбор структуры таблицы (эффект виден уже
на 26 партициях, см. ниже). Не по году: партиция в 2.5 млн строк почти
не отличается от исходной таблицы. Месяц даёт ~208 тысяч строк и 45 MB
на партицию — размер, при котором и партиция, и её локальные индексы
целиком помещаются в память.

**Шаг 4. Какие запросы должны выиграть от pruning.**

| Запрос API | Есть ли `created_at` в `WHERE` | Ожидание |
|---|---|---|
| `GET /orders?from=&to=` | да | одна-две партиции |
| `GET /orders/statistics?from=&to=` | да | одна партиция |
| `GET /orders/{id}` | **нет** | pruning не сработает |
| `GET /orders/my` | нет (только `user_id`) | pruning не сработает |

Последние две строки — не недосмотр, а осознанно принятая цена.
Ниже она измерена.

### Шаг 5. Партиции

```sql
CREATE TABLE public.orders_partitioned (
    id           uuid                     NOT NULL,
    user_id      uuid                     NOT NULL,
    total_amount numeric(18,2)            NOT NULL,
    status       character varying(50)    NOT NULL,
    created_at   timestamp with time zone NOT NULL,
    updated_at   timestamp with time zone
) PARTITION BY RANGE (created_at);

DO $$
DECLARE d date := date '2024-09-01';
BEGIN
    WHILE d < date '2026-10-01' LOOP
        EXECUTE format(
            'CREATE TABLE public.%I PARTITION OF public.orders_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            'orders_p_' || to_char(d, 'YYYY_MM'), d, d + INTERVAL '1 month');
        d := (d + INTERVAL '1 month')::date;
    END LOOP;
END $$;

CREATE TABLE public.orders_p_default PARTITION OF public.orders_partitioned DEFAULT;
```

25 месячных партиций плюс DEFAULT. Перенос 5 000 003 строк занял 3.8 с.

Индексы создаются на родителе — в партициях появляются локальные:

```sql
ALTER TABLE public.orders_partitioned
    ADD CONSTRAINT "PK_orders_partitioned" PRIMARY KEY (id, created_at);
CREATE INDEX "IX_orders_p_created_at"         ON public.orders_partitioned (created_at DESC);
CREATE INDEX "IX_orders_p_user_id_created_at" ON public.orders_partitioned (user_id, created_at DESC);
CREATE INDEX "IX_orders_p_id"                 ON public.orders_partitioned (id);
```

```
  partition_name  | count  | size
------------------+--------+-------
 orders_p_2024_09 | 141919 | 31 MB
 orders_p_2024_10 | 208430 | 45 MB
 …                |    …   |   …
 orders_p_2026_08 | 208631 | 45 MB
 orders_p_2026_09 |  66544 | 14 MB
```

Суммарно 1074 MB против 1067 MB у обычной таблицы — партиционирование
само по себе места почти не добавляет.

**Первое ограничение, с которым пришлось столкнуться.** Первичный ключ
партиционированной таблицы обязан содержать ключ партиционирования,
поэтому `PRIMARY KEY (id)` превратился в `PRIMARY KEY (id, created_at)`.
Следствие: внешний ключ `order_items.order_id → orders(id)` сохранить
нельзя — ссылаться на одиночный `id` больше не на что. Компенсация —
триггер `BEFORE DELETE`, который удаляет позиции заказа вручную;
текст в [`sql/part10-cutover.sql`](sql/part10-cutover.sql).

### Шаг 6. Проверка реальных запросов API

Первые замеры оказались нечестными: обычная таблица читала 54 372
страницы с диска, партиционированная — 2 273 из памяти. Поэтому каждый
запрос выполнялся **трижды подряд** по одной и той же таблице, и
в таблицу ниже вынесен третий прогон
([`sql/part8b-fair-comparison.sql`](sql/part8b-fair-comparison.sql)).

| Запрос API | Обычная | Партиционированная | Итог |
|---|---|---|---|
| `GET /orders?from=&to=` (страница за месяц) | 0.596 мс | **0.266 мс** | ×2.2 |
| `GET /orders/statistics?from=&to=` | 544.866 мс, 54 385 страниц | **31.271 мс, 2 273 страницы** | **×17.4** |
| `GET /orders/{id}` | 0.009 мс | **0.111 мс** | ×12 **хуже** |
| `GET /orders/my` | 0.040 мс | **0.671 мс** | ×17 **хуже** |
| Годовая аналитика | 121.976 мс, 54 601 страница | 125.802 мс, **27 324 страницы** | время то же, ввод-вывод вдвое меньше |
| Удаление месяца истории | 74.213 мс только на подсчёт строк | **`DROP TABLE` за 5.755 мс** | иной порядок |

#### Запрос, который выиграл больше всех

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT date_trunc('day', created_at) AS day, count(*), sum(total_amount)
FROM public.orders_partitioned
WHERE created_at >= '2026-07-01' AND created_at < '2026-08-01'
GROUP BY 1;
```

```
 GroupAggregate  (actual time=101.089..122.059 rows=31 loops=1)
   Buffers: shared hit=2276
   ->  Seq Scan on orders_p_2026_07 orders_partitioned
         Filter: ((created_at >= '2026-07-01') AND (created_at < '2026-08-01'))
         Buffers: shared hit=2273
 Execution Time: 31.271 ms
```

Вместо `Bitmap Index Scan` по индексу всей таблицы и последующего чтения
53 499 разбросанных страниц — обычный `Seq Scan` по партиции целиком.
Когда нужен весь месяц, последовательное чтение 2 273 страниц выигрывает
у любого индекса.

#### Запрос, который проиграл

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM public.orders_partitioned WHERE id = 'bbbbbbbb-…-003';
```

```
 Append  (actual time=14.095..14.106 rows=1 loops=1)
   ->  Index Scan using orders_p_2024_09_id_idx on orders_p_2024_09  (rows=0)
   ->  Index Scan using orders_p_2024_10_id_idx on orders_p_2024_10  (rows=0)
   …  ещё 23 таких же …
   ->  Index Scan using orders_p_2026_09_id_idx on orders_p_2026_09  (rows=1)
   ->  Seq Scan on orders_p_default                                  (rows=0)
 Planning Time: 9.144 ms
 Execution Time: 14.391 ms
```

Двадцать шесть обращений к индексам ради одной строки. Это и есть
scatter-gather из теории, вживую. На прогретом кэше запрос отрабатывает
за 0.111 мс — но на обычной таблице он же занимает 0.009 мс, и планирование
дорожает с 0.011 до 0.133 мс.

**Что с этим делать.** Дата у клиента почти всегда есть: список заказов
отдаёт `created_at` вместе с `id`, ссылка на заказ может нести и её.
Если добавить дату в условие, pruning возвращается:

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM public.orders_partitioned
WHERE id = 'bbbbbbbb-…-003'
  AND created_at >= '2026-09-01' AND created_at < '2026-10-01';
```

```
 Index Scan using orders_p_2026_09_id_idx on orders_p_2026_09 orders_partitioned
   Index Cond: (id = 'bbbbbbbb-…-003'::uuid)
 Execution Time: 0.022 ms
```

0.022 мс — быстрее, чем на непартиционированной таблице, потому что
локальный индекс одной партиции мельче общего. То же и со списком
заказов клиента: без периода 0.671 мс (`Merge Append` по 26 партициям),
с периодом — 0.195 мс.

**Вывод по шагу 6: партиционирование не бесплатно для точечных запросов,
и цена платится ровно там, где в условии нет ключа. Лечится это не
настройками СУБД, а API: передавать период вместе с идентификатором.**

#### Что партиционирование сделало с записью

Опыт на двух одинаковых таблицах с одинаковыми индексами
([`sql/part11-write-cost.sql`](sql/part11-write-cost.sql)), по 500 000 строк:

| | Обычная | 25 партиций |
|---|---|---|
| Вставка 500 000 строк | 1885.634 мс | **1806.332 мс** |
| Страниц затронуто | 3 363 423 | **2 507 254** |
| Размер | 84 MB | 84 MB |
| `SELECT count(*)` за месяц | 39.948 мс | **1.799 мс** |
| Время планирования | 0.922 мс | 0.731 мс |
| Удаление месяца | `DELETE` 11.231 мс + `VACUUM` | `DROP TABLE` 6.971 мс |

Ожидание было, что tuple routing замедлит вставку. На практике
партиционированная таблица оказалась даже чуть быстрее: локальные
B-деревья ниже, и на поддержание индексов уходит меньше обращений
к страницам — 2.5 млн против 3.4 млн. Это не значит, что запись всегда
дешевеет; это значит, что на разумном числе партиций маршрутизация
строк стоит меньше, чем экономит уменьшение индексов.

### Шаги 7–9: автоматизация, контроль, alert

Всё три пункта закрыты тем же механизмом, что и в частях 10–11: таблица
`public.orders_partitioned` просто добавлена в конфигурацию job'а
как вторая обслуживаемая, с месячным шагом и горизонтом в три месяца.

```json
{ "Schema": "public", "Table": "orders_partitioned", "Interval": "Monthly",
  "NamePrefix": "orders_p_", "HorizonPeriods": 3 }
```

При старте сервиса job досоздал `orders_p_2026_10`, `orders_p_2026_11`
и `orders_p_2026_12`; проверка видит обе таблицы и рапортует по каждой
отдельно:

```json
{ "table": "public.orders_partitioned", "status": "OK", "horizon": 3,
  "expected": ["orders_p_2026_09","orders_p_2026_10","orders_p_2026_11","orders_p_2026_12"],
  "missing": [] }
```

### О переключении сервиса

Замеры сделаны на копии `orders_partitioned`, созданной рядом с рабочей
таблицей; сама `orders` не переименовывалась. Транзакция переключения
подготовлена и лежит в [`sql/part10-cutover.sql`](sql/part10-cutover.sql)
вместе с процедурой отката — но на живой базе в рамках лабораторной
она не выполнялась. Это осознанное решение: переключение схемы
работающего сервиса делается в окно обслуживания и после бэкапа,
а не между двумя замерами.

---

## Что показывать на защите

```
Большая таблица         orders — 5 000 003 строки, 1067 MB, 25 месяцев
      ↓
Выбор ключа             created_at — есть в WHERE аналитики, неизменен
      ↓
Выбор стратегии         RANGE по месяцу — 208 тыс. строк и 45 MB на партицию
      ↓
Партиции                25 месячных + DEFAULT
      ↓
Partition pruning       статистика за месяц: 544.9 мс -> 31.3 мс, 54 385 -> 2 273 страницы
      ↓
Автоматическое создание CreatePartitionsJob, горизонт 3 периода
      ↓
Проверка                GET /api/partitions/health -> OK
      ↓
Сбой                    DELETE /api/partitions/lab3.events/events_2026_09_14
      ↓
ALERT                   через 27 секунд, в лог и в канал
      ↓
Восстановление          POST /api/partitions/ensure
      ↓
OK                      recovery-уведомление, downtime 1.9 min
```

Команды для живого показа:

```bash
K='X-API-Key: your-api-key-here-change-in-production'

curl -s -H "$K" http://localhost:8090/api/partitions/health | jq       # OK
curl -s -X DELETE -H "$K" \
     http://localhost:8090/api/partitions/lab3.events/events_2026_09_14 # авария
docker logs -f alert_sink                                              # alert пришёл
curl -s -X POST -H "$K" http://localhost:8090/api/partitions/check | jq # suppressed
curl -s -X POST -H "$K" http://localhost:8090/api/partitions/ensure | jq # починка
curl -s -X POST -H "$K" http://localhost:8090/api/partitions/check | jq # recovery
```

---

## Контрольные вопросы

**1. Что такое partitioning?**
Разделение одной логической таблицы на несколько физических (партиций)
в рамках одного сервера. Приложение продолжает писать `SELECT * FROM orders`,
а СУБД сама решает, в какую подтаблицу идти. Это не шардирование: все
партиции живут в одной базе и в одной транзакции.

**2. Чем partitioning отличается от индекса?**
Индекс отвечает на вопрос «где внутри таблицы лежит нужная строка»,
партиционирование — «какие данные можно вообще не читать». Единица работы
у индекса — строка, у партиционирования — физическая таблица. Отсюда и
разные возможности: индекс не умеет удалить миллион строк за 12 мс,
партиционирование не умеет найти одну строку.

**3. Какие стратегии partitioning поддерживает PostgreSQL?**
RANGE (диапазоны значений), LIST (списки значений) и HASH (остаток от
деления хеша). Плюс DEFAULT-партиция для RANGE и LIST — приёмник значений,
не попавших ни в один диапазон или список. Партиции можно вкладывать:
партиция сама может быть партиционированной таблицей.

**4. Когда использовать RANGE?**
Когда у ключа есть естественный порядок и запросы работают с интервалами:
даты, суммы, версии. Главный признак — наличие жизненного цикла у данных
и требование удалять или архивировать старое.

**5. Когда использовать LIST?**
Когда значений ключа конечное и известное множество, а запросы фильтруют
по равенству: тип клиента, страна, регион, тенант. Обязательна
DEFAULT-партиция — иначе новое значение уронит `INSERT`.

**6. Когда использовать HASH?**
Когда естественного разделения нет, но нужна равномерность: снять нагрузку
с одной «горячей» партиции, уменьшить локальные индексы, разложить данные
по дискам. В опыте 4 млн строк разошлись по четырём партициям с отклонением
0.12 п. п.

**7. Как выбрать partition key?**
Четыре требования подряд. Ключ должен присутствовать в `WHERE` большинства
запросов (иначе pruning не сработает и станет только хуже); он должен быть
неизменяемым (смена ключа = физический перенос строки между партициями);
он должен давать партиции соизмеримого размера; и по нему должны проходить
операции жизненного цикла — удаление и архивация.

**8. Что такое partition pruning?**
Исключение партиций из плана на основании границ, записанных в каталоге.
Планировщик сопоставляет условие `WHERE` с `FOR VALUES …` каждой партиции
и выбрасывает те, которые заведомо не содержат искомых строк. Работает
на этапе планирования (константы) и на этапе выполнения (параметры
подготовленных запросов).

**9. Почему pruning может не сработать?**
Главная причина — ключа партиционирования нет в `WHERE`. Кроме неё:
условие не сводится к границам (`WHERE date_trunc('month', created_at) = …`
вместо диапазона по самому столбцу); для HASH — условие является
диапазоном, а не равенством; значение не перечислено ни в одной LIST-партиции,
и приходится читать DEFAULT; условие соединено через `OR` с условием
по другому столбцу.

**10. Можно ли использовать индексы вместе с partitioning?**
Не только можно, а нужно — это и есть рабочая комбинация. `CREATE INDEX`
на родительской таблице создаёт локальные индексы во всех партициях
и автоматически создаёт их в каждой новой. В опыте связка дала 0.198 мс
против 97.767 мс на одном pruning — в 494 раза.

**11. Что произойдёт, если подходящей партиции нет?**
`INSERT` падает с `ERROR: no partition of relation "…" found for row`.
Не молча, не «в никуда» — приложение получает ошибку. Если объявлена
DEFAULT-партиция, строка попадёт в неё.

**12. Зачем создавать будущие партиции заранее?**
Потому что отсутствие партиции ломает запись, а не чтение, и ломает
мгновенно. Запас на несколько периодов вперёд превращает «сервис
не принимает заказы» в «есть три дня на то, чтобы починить job».

**13. Почему создание партиций должно быть автоматизировано?**
Ручная операция, которую нужно повторять каждый день или месяц годами,
будет забыта — вопрос только в том, когда. Автоматизация ещё и делает
процесс воспроизводимым: одна и та же логика создаёт партиции в проде,
на стенде и в тестах.

**14. Чем логирование ошибки отличается от alerting?**
Направлением. Лог пассивен: он ждёт, пока в него посмотрят. Alert активен:
он сам находит человека. В реализации это видно буквально — при каждой
проверке проблема пишется в лог, а уведомление уходит только на смену
состояния.

**15. Что такое recovery alert?**
Сообщение о том, что проблема устранена. Без него дежурный не знает,
закрыт инцидент или просто перестали приходить сообщения. В реализации
recovery несёт и время простоя, посчитанное от `first_seen_at`:
`Downtime: 1.9 min`.

**16. Почему нельзя бесконечно отправлять одинаковый alert?**
Из-за усталости от уведомлений: канал, в который каждые пять минут падает
одно и то же, перестают читать — и пропускают следующую, настоящую аварию.
Поэтому уведомление отправляется на переход состояния, а напоминание —
не чаще чем раз в `RenotifyAfter` (в конфигурации 6 часов).

**17. Всегда ли partitioning ускоряет запросы?**
Нет, и это измерено на собственной базе. `GET /orders/{id}` замедлился
в 12 раз (26 обращений к индексам вместо одного), `GET /orders/my` —
в 17 раз. Ускорились только те запросы, где ключ партиционирования есть
в условии: статистика за месяц — в 17.4 раза.

**18. Какие проблемы возникают при неправильном выборе размера партиций?**
С обеих сторон свои. *Слишком мелкие*: сотни и тысячи партиций раздувают
метаданные, планировщик тратит время на разбор структуры, растёт нагрузка
на autovacuum — на 26 партициях планирование точечного запроса уже стоит
0.133 мс против 0.011 мс. *Слишком крупные*: партиция перестаёт помещаться
в память, и всё возвращается к исходной задаче — сканирование огромной
таблицы. Отдельная беда — перекос: в опыте с ценами `products_expensive`
оказалась в сорок раз больше `products_cheap`, и для запросов по дорогим
товарам партиционирование не дало ничего.

---

## Итоги

**Три вещи, которые партиционирование делает лучше всего.**

1. **Удаляет историю.** `DROP TABLE` партиции — 5.755 мс на 141 919 строк
   и 31 MB. `DELETE` того же объёма — десятки-сотни миллисекунд плюс
   `VACUUM` плюс раздувание таблицы. Это единственная выгода, которую
   нельзя получить индексом ни при каких условиях.
2. **Ускоряет запросы по периоду.** Статистика за месяц: 544.9 мс → 31.3 мс,
   54 385 страниц → 2 273. Причём не за счёт индекса, а за счёт того,
   что `Seq Scan` по нужной партиции дешевле индексного чтения разбросанных
   страниц большой таблицы.
3. **Держит индексы в памяти.** Локальный индекс партиции в 25 раз мельче
   общего, ниже по высоте дерева. Побочный эффект — вставка стала даже
   чуть быстрее: 2.5 млн обращений к страницам против 3.4 млн.

**Три вещи, за которые приходится платить.**

1. **Точечные запросы без ключа замедляются.** `GET /orders/{id}` — ×12,
   `GET /orders/my` — ×17. Лечится не настройками, а передачей периода
   в запрос: с датой в условии те же запросы дают 0.022 мс и 0.195 мс,
   то есть **быстрее**, чем до партиционирования.
2. **Ломаются внешние ключи.** `PRIMARY KEY (id)` обязан стать
   `PRIMARY KEY (id, created_at)`, и `order_items.order_id → orders(id)`
   становится невозможным. Пришлось заменить каскад триггером.
3. **Появляется то, что может сломаться ночью.** Партиции нужно создавать,
   их наличие нужно проверять, о пропаже нужно сообщать. Это не побочная
   задача, а половина работы: части 10 и 11 по объёму кода сопоставимы
   со всем остальным.

**Главный вывод.** Партиционирование — это не `PARTITION BY RANGE (...)`,
а решение о том, какой запрос вы готовы замедлить ради того, чтобы другой
ускорился. В этой базе выбор был такой: замедлить точечный поиск по `id`
на 0.1 мс, чтобы ускорить месячную аналитику на полсекунды и превратить
удаление истории из ночной операции в одну команду. Обратный выбор был бы
ошибкой — и именно поэтому решение нужно принимать по замерам, а не по
описанию возможностей.

---

## Состав работы

| Файл | Что внутри |
|---|---|
| [`sql/part1-range-date.sql`](sql/part1-range-date.sql) | Части 1–2: RANGE по дате, partition pruning, runtime pruning |
| [`sql/part2-range-numeric.sql`](sql/part2-range-numeric.sql) | Часть 3: RANGE по цене |
| [`sql/part3-list.sql`](sql/part3-list.sql) | Части 4–5: LIST и DEFAULT-партиция, вынос данных из DEFAULT |
| [`sql/part4-hash.sql`](sql/part4-hash.sql) | Часть 6: HASH, равномерность, почему не годится для retention |
| [`sql/part5-index.sql`](sql/part5-index.sql) | Части 8–9: локальные индексы, границы применимости |
| [`sql/part6-orders-baseline.sql`](sql/part6-orders-baseline.sql) | Часть 12: замеры до партиционирования |
| [`sql/part7-orders-partition.sql`](sql/part7-orders-partition.sql) | Часть 12: создание 25 месячных партиций и перенос данных |
| [`sql/part8-orders-after.sql`](sql/part8-orders-after.sql) | Часть 12: планы после партиционирования |
| [`sql/part8b-fair-comparison.sql`](sql/part8b-fair-comparison.sql) | Часть 12: честное сравнение на прогретом кэше |
| [`sql/part9-partition-automation.sql`](sql/part9-partition-automation.sql) | Части 10–11: таблица состояния alert'ов, витрина `v_partitions` |
| [`sql/part10-cutover.sql`](sql/part10-cutover.sql) | Транзакция переключения сервиса и откат (не выполнялась) |
| [`sql/part11-write-cost.sql`](sql/part11-write-cost.sql) | Цена партиционирования для записи |
| [`jobs/`](jobs) | `CreatePartitionsJob`, `PartitionHealthCheckJob`, `PartitionManager`, notifiers, контроллер |
| [`tools/alert-sink.py`](tools/alert-sink.py) | Локальный приёмник webhook'ов для демонстрации alert'а |
| [`raw/`](raw) | Сырой вывод всех прогонов |
