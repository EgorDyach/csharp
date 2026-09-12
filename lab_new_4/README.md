# Лабораторная работа №4. Масштабирование чтения PostgreSQL: Primary + Replica

Streaming replication для сервиса ChakChakShop: запись на Primary, списочные
чтения — с Replica. Все цифры получены на живом стенде с базой в 5 млн
заказов, сырые логи прогонов лежат в [`raw/`](raw).

---

## Стенд

| | Primary | Replica |
|---|---|---|
| Контейнер | `chakchakshop_postgres` | `chakchakshop_postgres_replica` |
| Образ | `postgres:16-alpine` | `postgres:16-alpine` |
| Порт снаружи | `localhost:5455` | `localhost:5456` |
| Адрес в сети compose | `postgres:5432` | `postgres_replica:5432` |
| Роль | принимает запись и чтение | только чтение |
| Размер кластера | 6.1 GB | копия |

```bash
psql -h localhost -p 5455 -U postgres -d chakchakshop   # Primary
psql -h localhost -p 5456 -U postgres -d chakchakshop   # Replica
```

### Порядок воспроизведения

```bash
./infra/01-prepare-primary.sh          # роль, слот, pg_hba
./infra/02-basebackup-replica.sh       # побайтовая копия кластера
docker compose up -d postgres_replica  # старт standby
./infra/03-proof-replication.sh        # части 3-4
./infra/05-service-reads-on-replica.sh # часть 5
./infra/04-replication-lag.sh          # часть 6
python3 infra/06-lag-through-api.py 150
```

---

## Часть 1. Primary и Replica

Фрагмент compose целиком — в [`infra/docker-compose.replica.yml`](infra/docker-compose.replica.yml).
Главное в нём то, чего там **нет**: у реплики не задан ни один параметр
репликации.

```yaml
  postgres_replica:
    image: postgres:16-alpine
    container_name: chakchakshop_postgres_replica
    shm_size: '1gb'
    ports:
      - '5456:5432'
    volumes:
      - postgres_replica_data:/var/lib/postgresql/data
    healthcheck:
      test: ['CMD-SHELL', 'pg_isready -U postgres']
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - chakchakshop_network
```

Реплика не настраивается конфигом — она **восстанавливается из копии**.
`PGDATA` приходит целиком из `pg_basebackup` вместе с файлом
`standby.signal` и строкой `primary_conninfo`, поэтому контейнер с тем же
самым образом стартует не как обычная база, а как standby.

Кто есть кто, проверяется одной функцией:

```sql
SELECT pg_is_in_recovery();
```

```
Primary:  f
Replica:  t
```

---

## Часть 2. Streaming replication

### Что уже было готово

Образ `postgres:16-alpine` приходит с настройками, которых достаточно:

```
 wal_level             | replica
 max_wal_senders       | 10
 max_replication_slots | 10
 hot_standby           | on
```

`postgresql.conf` править не пришлось вообще. Не хватало двух вещей.

**Роль с правом репликации:**

```sql
CREATE ROLE replicator WITH REPLICATION LOGIN PASSWORD '...';
```

**Правило в `pg_hba.conf`:**

```
host replication replicator all scram-sha-256
```

Отдельная строка нужна потому, что репликационные подключения идут не в
базу, а в псевдо-базу `replication`, и обычное `host all all all` их
не покрывает. Без этой строки `pg_basebackup` отвечает
`no pg_hba.conf entry for replication connection`.

**Слот репликации** — не обязателен, но без него реплика,
отставшая сильнее чем на `wal_keep_size`, теряет нужные сегменты WAL
и больше не может догнать Primary:

```sql
SELECT pg_create_physical_replication_slot('replica_1_slot');
```

### Базовая копия

```bash
pg_basebackup -h postgres -p 5432 -U replicator \
              -D /pgdata -Fp -Xs -P -R -S replica_1_slot
```

```
5481378/5481378 kB (100%), 1/1 tablespace
```

| Флаг | Зачем |
|---|---|
| `-Fp` | копия обычным каталогом, её сразу можно подложить как PGDATA |
| `-Xs` | поток WAL забирается **параллельно** с копированием файлов, иначе на 5.5 GB нужные сегменты успеют смениться до конца копии |
| `-R` | сам создаёт `standby.signal` и пишет `primary_conninfo` — конфиг руками править не нужно |
| `-S` | копия сразу привязана к слоту |

Что положил `-R`:

```
primary_conninfo = 'user=replicator password=... host=postgres port=5432 ...'
primary_slot_name = 'replica_1_slot'
```

### Цепочка целиком

```
Primary изменяет данные
      ↓
изменение фиксируется в WAL              ← wal_level = replica
      ↓
процесс walsender читает WAL и шлёт по сети
      ↓
процесс walreceiver на Replica принимает и пишет в свой WAL
      ↓
Replica непрерывно проигрывает WAL        ← hot_standby = on
```

Первые строки в логе реплики — ровно эта последовательность:

```
LOG:  entering standby mode
LOG:  consistent recovery state reached at 7/5C001640
LOG:  database system is ready to accept read-only connections
LOG:  started streaming WAL from primary at 7/5D000000 on timeline 1
```

### Состояние репликации на Primary

```sql
SELECT * FROM pg_stat_replication;
```

```
 application_name |  client_addr  |   state   | sync_state |  sent_lsn  | write_lsn  | flush_lsn  | replay_lsn
------------------+---------------+-----------+------------+------------+------------+------------+------------
 walreceiver      | 192.168.160.9 | streaming | async      | 8/58ACA6C8 | 8/58ACA6C8 | 8/58ACA6C8 | 8/58ACA6C8
```

Четыре LSN — это четыре стадии, и они важны для понимания части 6:

| Колонка | Что означает |
|---|---|
| `sent_lsn` | Primary отправил в сеть |
| `write_lsn` | Replica записала в свой WAL |
| `flush_lsn` | Replica сбросила на диск |
| **`replay_lsn`** | Replica **применила** — именно это видно в `SELECT` |

Реплика может уже получить и сохранить изменение, но ещё не применить его.
Разрыв между `flush_lsn` и `replay_lsn` — это и есть то, что читатель
видит как устаревшие данные.

---

## Часть 3. Доказательство работы репликации

### Запись на Primary

```sql
INSERT INTO categories (id, name, description, created_at)
VALUES ('dddddddd-dddd-dddd-dddd-ddddddddddd1',
        'Реплика-тест',
        'Строка создана на Primary в ходе лабораторной №4',
        NOW());
```

```
                  id                  |     name     |          created_at
--------------------------------------+--------------+------------------------------
 dddddddd-dddd-dddd-dddd-ddddddddddd1 | Реплика-тест | 2026-09-12 12:35:04.07956+00
INSERT 0 1
```

### Чтение на Replica

```sql
SELECT id, name, description FROM categories
WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd1';
```

```
                  id                  |     name     |                   description
--------------------------------------+--------------+--------------------------------------------------
 dddddddd-dddd-dddd-dddd-ddddddddddd1 | Реплика-тест | Строка создана на Primary в ходе лабораторной №4
```

`UPDATE` доезжает так же: после смены имени на `Реплика-тест 12:35:04`
реплика отдаёт ровно это значение.

### Объёмы совпадают

Одни и те же три запроса на обоих узлах:

```sql
SELECT 'orders' AS t, count(*) FROM orders
UNION ALL SELECT 'users', count(*) FROM users
UNION ALL SELECT 'categories', count(*) FROM categories;
```

| Таблица | Primary | Replica |
|---|---|---|
| `orders` | 5 000 003 | 5 000 003 |
| `users` | 50 003 | 50 003 |
| `categories` | 4 | 4 |

Это не совпадение настроек, а физическая копия: реплика проигрывает
байты WAL, а не выполняет SQL заново.

---

## Часть 4. Replica работает только на чтение

Четыре попытки изменить данные на реплике:

```sql
INSERT INTO categories (...) VALUES (...);
UPDATE categories SET name = 'испорчено' WHERE ...;
DELETE FROM categories WHERE ...;
CREATE TEMP TABLE t_probe (x int);
```

```
ERROR:  cannot execute INSERT in a read-only transaction
ERROR:  cannot execute UPDATE in a read-only transaction
ERROR:  cannot execute DELETE in a read-only transaction
ERROR:  cannot execute CREATE TABLE in a read-only transaction
```

Запрещена даже временная таблица: любая запись требует выделения
номера транзакции, а standby не имеет права его выдавать.

```sql
SHOW transaction_read_only;
```

```
Primary:  off
Replica:  on
```

### Почему Replica нельзя использовать как независимую базу для записи

Дело не в том, что PostgreSQL «не разрешает». Дело в том, что запись
на реплику **сломала бы саму репликацию**.

Реплика находится в режиме вечного восстановления: она байт за байтом
повторяет файлы Primary. Собственная запись означала бы, что её файлы
разошлись с оригиналом, и следующая же порция WAL, описывающая
изменение «страницы №5», применилась бы к странице, которой на Primary
никогда не существовало. Это не конфликт данных, а разрушение кластера.

Отсюда и практические следствия для приложения:

- реплика — не второй сервер, а копия; писать в неё некуда, потому что
  всё написанное будет затёрто следующим же WAL-сегментом;
- разделение ролей должно жить в коде: отдельная строка подключения
  на запись и отдельная на чтение;
- «резервная база на случай падения Primary» — это не «вторая база для
  записи», а реплика, которую при аварии **повышают** до Primary
  отдельной процедурой (failover), после чего старый Primary обязан
  быть выведен из игры.

Читать при этом можно что угодно, включая тяжёлую аналитику:

```sql
SELECT date_trunc('month', created_at)::date AS month, count(*)
FROM orders WHERE created_at >= '2026-07-01' GROUP BY 1;
```

```
   month    | count
------------+--------
 2026-07-01 | 208061
 2026-08-01 | 208631
 2026-09-01 |  66544
```

---

## Часть 5. Чтение сервиса идёт через Replica

### Маршрутизация в коде

Добавлена фабрика подключений
([`code/IDbConnectionFactory.cs`](code/IDbConnectionFactory.cs),
[`code/DbConnectionFactory.cs`](code/DbConnectionFactory.cs)):

```csharp
public interface IDbConnectionFactory
{
    IDbConnection CreateWriteConnection();   // Primary
    IDbConnection CreateReadConnection();    // Replica, если настроена
    string ReadNodeName { get; }
    bool ReplicaConfigured { get; }
}
```

Если `ConnectionStrings:ReplicaConnection` пуста, чтение молча остаётся
на Primary: сервис обязан подниматься и без реплики.

```csharp
public IDbConnection CreateReadConnection() =>
    new NpgsqlConnection(_replicaConnectionString ?? _primaryConnectionString);
```

Строка подключения задаётся окружением:

```yaml
- ConnectionStrings__ReplicaConnection=Host=postgres_replica;Port=5432;Database=chakchakshop;Username=postgres;Password=postgres;ApplicationName=chakchakshop-api-read
```

`ApplicationName` задан намеренно: по нему подключения сервиса видно
в `pg_stat_activity` на реплике.

### Что именно переведено на Replica

В `DapperOrderRepository` на реплику ушли четыре метода:

```csharp
private IDbConnection CreateReadConnection() => _connections.CreateReadConnection();

// GetPagedAsync, GetCountAsync, GetByUserIdPagedAsync, GetCountByUserIdAsync
using var connection = CreateReadConnection();
```

| Ручка API | Узел | Почему |
|---|---|---|
| `GET /api/orders` | **replica** | список заказов, опоздавший на один свежий заказ, ничего не ломает |
| `GET /api/orders/my` | **replica** | то же самое |
| `GET /api/orders/{id}` | primary | клиент запрашивает заказ **сразу после** `POST /api/orders`; на реплике его может ещё не быть |
| `POST/PUT/DELETE /api/orders` | primary | запись всегда на Primary |

Отказ переводить точечное чтение по `id` — не осторожность, а прямое
следствие части 6: в 44 % случаев реплика ещё не успевает.

### Доказательство №1: куда сервис открывает подключения

```
GET /api/replication/where-am-i
```

```json
{
  "replicaConfigured": true,
  "readsGoTo": "replica",
  "writeConnection": { "inRecovery": false, "address": "192.168.160.4/32", "role": "primary" },
  "readConnection":  { "inRecovery": true,  "address": "192.168.160.9/32", "role": "replica" }
}
```

`pg_is_in_recovery()` возвращает `true` только на standby — подмены здесь быть не может.

### Доказательство №2: заголовок ответа

```
GET /api/orders                -> X-Db-Node: replica
GET /api/orders/my             -> X-Db-Node: replica
GET /api/orders/{id}           -> X-Db-Node: primary
```

### Доказательство №3: счётчики самой Replica

30 запросов `GET /api/orders`, до и после — `pg_stat_database` на реплике:

```
tup_returned до:      357 434 597
tup_returned после:   507 471 861
прочитано строк:      150 037 264
```

Сто пятьдесят миллионов строк на тридцать запросов — это по 5 млн на
запрос, то есть ровно `SELECT COUNT(*) FROM orders` из `GetCountAsync`,
который нужен пагинации для подсчёта общего числа страниц. Полный проход
по пятимиллионной таблице на каждый показ списка.

**И это лучшая иллюстрация того, зачем нужен read scaling:** запрос
как был неэффективным, так и остался — но теперь он грузит реплику,
а не тот узел, который принимает заказы.

### Доказательство №4: подключения на реплике

```sql
SELECT application_name, state, backend_type FROM pg_stat_activity
WHERE datname = 'chakchakshop' AND application_name <> '';
```

```
   application_name    | state |  backend_type
-----------------------+-------+----------------
 chakchakshop-api-read | idle  | client backend
```

### Запись по-прежнему на Primary

`POST /api/orders` создаёт заказ:

```json
{ "id": "786731e5-b2a3-4a28-a636-bfaa6432c7f8", "totalAmount": 950.00, "status": "Pending",
  "items": [ { "productId": "cccccccc-...-ccc1", "quantity": 1, "totalPrice": 950.00 } ] }
```

### Попутно исправленный баг

`POST /api/orders` в исходном коде не работал **никогда**: в
`OrderService.CreateOrderAsync` позиции заказа собираются до того, как
у заказа появляется идентификатор, и `OrderId` у них так и оставался
`Guid.Empty`.

```
23503: insert or update on table "order_items"
       violates foreign key constraint "FK_order_items_orders_order_id"
```

Починено одной строкой; без неё часть 5 нечем было бы демонстрировать —
запись через сервис просто падала:

```csharp
// Позиции собираются до того, как у заказа появляется идентификатор,
// поэтому связь проставляется здесь.
foreach (var item in orderItems)
{
    item.OrderId = order.Id;
}
```

---

## Часть 6. Replication lag

### Опыт 1. Одиночная запись в спокойной системе

Запись на Primary и сразу `SELECT` на Replica — значение уже на месте.
Отставание в этот момент:

```
 replay_lag_bytes |    write_lag    |    flush_lag    |    replay_lag
------------------+-----------------+-----------------+-----------------
                0 | 00:00:00.000551 | 00:00:00.000811 | 00:00:00.00118
```

Чуть больше миллисекунды. Поймать окно двумя `docker exec` невозможно:
один такой вызов стоит около 100 мс — в сто раз больше самого отставания.
Нужен либо поток записи, либо измерение внутри одного процесса.

### Опыт 2. Под нагрузкой записи

**2a. Одна большая транзакция** — 3 000 000 строк одним `INSERT`.
Отставание по WAL дошло до **52 MB**, но счётчики строк на узлах
всё время совпадали:

```
время      |      Primary |      Replica | WAL-отставание
-----------+--------------+--------------+----------------
12:36:10   |            0 |            0 |          28 MB
12:36:11   |            0 |            0 |          52 MB
12:36:18   |      3000000 |      3000000 |        0 bytes
```

Причина в том, что до `COMMIT` вставку не видит ни один из узлов.
Отставание было настоящим — просто оно не проявлялось в данных.
**Видимость транзакционна, а репликация побайтова, и это разные вещи.**

**2b. Шестьдесят мелких транзакций** по 50 000 строк. Здесь вскрылась
проблема самого метода: чтобы сравнить счётчики, нужно опросить два узла,
а между двумя запросами на Primary успевает закоммититься следующая пачка.
Наивное вычитание давало бессмыслицу вплоть до отрицательных чисел
(«реплика впереди Primary»).

Замер переделан «в скобках»: счётчик Primary читается до и после чтения
Replica, и выборка засчитывается, только если оба значения совпали.

```
время      |      Primary |      Replica | разница | WAL-отставание | замер
-----------+--------------+--------------+---------+----------------+---------
12:39:55   |       950000 |      1000000 |       ? |          19 MB | грязный
12:39:55   |      1200000 |      1300000 |       ? |          11 MB | грязный
12:39:59   |      3000000 |      3000000 |       0 |        0 bytes | чистый
```

Честный вывод: **пока запись идёт, чистую выборку получить не удалось
ни разу** — писатель коммитит быстрее, чем внешний наблюдатель успевает
опросить два узла. А как только запись прекращается, узлы совпадают.
Отставание в этом опыте измеримо только в байтах WAL, но не в строках.

### Опыт 3. Детерминированное окно

`recovery_min_apply_delay` заставляет Replica придержать применение уже
полученного WAL. Это штатный параметр: так делают реплику, отстающую
на час, чтобы успеть отменить ошибочный `DELETE`.

```sql
ALTER SYSTEM SET recovery_min_apply_delay = '15s';
SELECT pg_reload_conf();
```

```
Primary отдаёт:  delayed-12:36:39
Replica отдаёт:  lag-probe-1
                 ^^^ старое значение при уже записанном новом
```

Отставание в этот момент, с двух сторон:

```
Primary:  behind_bytes = 96 bytes,  replay_lag = 00:00:00.185747
Replica:  received = 7/8F396738, replayed = 7/8F3966D8
```

Реплика **получила** байты (`received` больше `replayed`), но не применила.
Дальше значение догнало само:

```
12:36:39  replica: lag-probe-1
12:36:45  replica: lag-probe-1
12:36:52  replica: lag-probe-1
12:36:55  replica: delayed-12:36:39
```

### Опыт 4. Через собственный API, без всяких ухищрений

Самое интересное. `POST /api/replication/lag-demo` делает две вещи
подряд внутри одного обработчика, без единой паузы: пишет маркер на
Primary и тут же читает то же поле на Replica.

```csharp
using var write = _connections.CreateWriteConnection();
await write.ExecuteScalarAsync<DateTime>("INSERT ... ON CONFLICT DO UPDATE ...");

// Никаких Task.Delay: читаем ровно в тот момент, когда Primary подтвердил COMMIT.
using var read = _connections.CreateReadConnection();
var seenOnReplica = await read.ExecuteScalarAsync<string?>("SELECT name FROM categories WHERE id = ...");
```

150 вызовов подряд ([`raw/part6b-lag-through-api.log`](raw/part6b-lag-through-api.log)):

```
  успешных вызовов:   150
  свежих чтений:      84
  устаревших чтений:  66
  ошибок:             0
  доля промахов:      44.0 %
  промах: интервал запись→чтение  мин 0.652 / медиана 1.869 / макс 13.176 мс
  успех:  интервал запись→чтение  мин 0.923 / медиана 2.564 / макс 10.015 мс
```

**В 44 % случаев чтение сразу после записи вернуло устаревшее значение.**
Без искусственных задержек, без нагрузки, на двух контейнерах внутри
одной машины, где сеть между узлами — это петля.

Отдельно стоит посмотреть на распределения: интервалы «запись → чтение»
у промахов и у попаданий **перекрываются**. Промах случается не потому,
что чтение пришло слишком быстро, а потому, что это гонка: реплика
применяет WAL параллельно, и кто успеет первым — вопрос случая.

### Чем мерить отставание в проде

```sql
-- со стороны Primary: сколько байт реплика не применила
SELECT pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn))
FROM pg_stat_replication;

-- со стороны Replica: на сколько секунд позади
SELECT now() - pg_last_xact_replay_timestamp();
```

Осторожно со вторым запросом. В простое, когда на Primary нет новых
транзакций, `now() - pg_last_xact_replay_timestamp()` растёт сам по себе:
на нашем стенде он показывал 16 секунд при нулевом отставании, потому
что за эти 16 секунд просто никто ничего не писал. Метрика осмысленна
только под непрерывным потоком записи; надёжнее считать отставание
в байтах WAL.

### Главный вывод части 6

Репликация не означает мгновенную синхронизацию. Между `COMMIT` на
Primary и моментом, когда изменение станет видно на Replica, существует
окно. На этом стенде оно составляет единицы миллисекунд — и этого уже
достаточно, чтобы почти половина запросов «прочитай то, что только что
записал» вернула старые данные.

Отсюда правило, по которому и разделены ручки сервиса: на реплику
отправляется то чтение, которое **переживёт отставание**. Список заказов
переживёт. Чтение только что созданного заказа по его идентификатору —
нет.

---

## Контрольные вопросы

**1. Чем Primary отличается от Replica?**
Primary принимает запись и ведёт WAL; Replica находится в режиме вечного
восстановления и только проигрывает полученный от Primary WAL. Технически
различие проверяется одной функцией: `pg_is_in_recovery()` возвращает
`false` на Primary и `true` на Replica. Следствие — на реплике
`transaction_read_only = on`, и любая запись отвергается.

**2. Почему запись выполняем на Primary?**
Потому что источник истины один. Реплика побайтово повторяет файлы
Primary; собственная запись развела бы их файлы, и следующая же порция
WAL применилась бы к странице, которой на Primary не существует — это
разрушило бы кластер, а не создало конфликт данных. Плюс при двух
пишущих узлах пришлось бы решать конфликты одновременных изменений одной
строки, чего физическая репликация не умеет в принципе.

**3. Как изменение из Primary попадает на Replica?**
Primary фиксирует изменение в WAL. Процесс `walsender` читает новые
записи WAL и передаёт их по сети. Процесс `walreceiver` на реплике
принимает поток, пишет в свой WAL и сбрасывает на диск, а процесс
восстановления применяет записи к файлам данных. По сети идут не
SQL-запросы, а бинарный журнал: «в блоке №5 изменить байты с такого-то
смещения».

**4. Что такое WAL в контексте репликации?**
Write-Ahead Log — журнал, в который изменение попадает **раньше**, чем
в сами файлы таблиц. Изначально он нужен для восстановления после сбоя,
но именно он оказался идеальным форматом передачи: последовательный,
компактный и уже содержащий все изменения. Репликация в PostgreSQL — это
и есть трансляция WAL на другой узел. Поэтому реплика получает изменения
«бесплатно», без повторного выполнения SQL и без нагрузки на планировщик.

**5. Что такое replication lag?**
Задержка между моментом, когда изменение зафиксировано на Primary, и
моментом, когда оно применено на Replica и стало видимым для читателя.
Измеряется в байтах WAL (`pg_wal_lsn_diff`) или во времени
(`replay_lag`, `now() - pg_last_xact_replay_timestamp()`). В нашем опыте
медиана окна — около 1.9 мс.

**6. Почему следующий SELECT после INSERT может увидеть старые данные, если отправить его на Replica?**
Потому что репликация асинхронная: Primary отвечает клиенту «готово»
сразу после записи в собственный WAL, не дожидаясь реплики. Пока реплика
принимает, сохраняет и применяет эти байты, проходит время, и чтение,
попавшее в это окно, вернёт прежнее значение. Измерено: 66 промахов из
150 попыток, то есть 44 %. Это и называется eventual consistency —
согласованность наступает, но не мгновенно.

**7. Что именно масштабируется при Read Scaling: скорость одного запроса или способность обслуживать больше чтений?**
Пропускная способность, а не скорость. Один и тот же `SELECT` на реплике
выполняется не быстрее — это та же СУБД с теми же данными и тем же
планом. Выигрыш в том, что запросов одновременно можно обслужить больше
и что тяжёлое чтение перестаёт мешать записи. Наш пример:
`SELECT COUNT(*) FROM orders` по 5 млн строк на каждый показ списка
никуда не делся и быстрее не стал — но он больше не отнимает диск
и процессор у того узла, который принимает заказы.

**8. Почему наличие Replica не отменяет необходимость индексов и оптимизации SQL?**
Потому что реплика копирует данные, а не переписывает запросы. Плохой
план остаётся плохим на любом узле: полный проход по пяти миллионам
строк на реплике стоит ровно столько же, сколько на Primary. Более того,
реплика наследует все индексы Primary один в один — своих у неё быть не
может, потому что файлы должны совпадать побайтово. Репликация
масштабирует количество читателей, оптимизация — стоимость одного
чтения; одно не заменяет другое. И есть обратный эффект: тяжёлые
долгие запросы на реплике конфликтуют с применением WAL и могут
отставание увеличить.

**9. CAP-теорема.**
В распределённой системе одновременно достижимы только два свойства из
трёх: **C** — согласованность (любое чтение возвращает последнее
записанное значение), **A** — доступность (каждый живой узел отвечает
на каждый запрос), **P** — устойчивость к разделению сети.

Поскольку сеть рвётся независимо от наших желаний, **P** в реальной
распределённой системе не выбирают — его принимают как данность.
Настоящий выбор идёт между C и A: при разрыве связи узел либо
отказывает в ответе, сохраняя согласованность, либо отвечает
потенциально устаревшими данными, сохраняя доступность.

Наша схема — наглядный пример выбора **AP**. Асинхронная репликация
означает, что реплика отвечает всегда, но иногда старыми данными: те
самые 44 % промахов. Выбор в пользу **CP** тоже возможен — это
синхронная репликация (`synchronous_commit = on` плюс
`synchronous_standby_names`), где Primary не подтверждает транзакцию,
пока реплика не запишет её у себя. Тогда устаревших чтений не будет,
но каждая запись начнёт стоить сетевого round-trip, а падение реплики
остановит запись на Primary. Для интернет-магазина, где список заказов
может опоздать на две миллисекунды, а оформление заказа опаздывать
не должно, выбран AP — и именно поэтому чтение по `id` оставлено на
Primary: там согласованность нужна, и её берут не настройкой СУБД,
а маршрутизацией запроса.

---

## Итоги

**Что получилось.**

1. Два экземпляра PostgreSQL: Primary на 5455, Replica на 5456, между
   ними streaming replication через слот, `state = streaming`.
2. Изменение с Primary доезжает до Replica: проверено `INSERT`, `UPDATE`
   и сверкой счётчиков на 5 млн строк.
3. Replica отвергает любую запись, включая временные таблицы.
4. Реальные ручки сервиса `GET /api/orders` и `GET /api/orders/my`
   обслуживаются репликой — подтверждено тремя независимыми способами:
   `pg_is_in_recovery()` на самом подключении, заголовком `X-Db-Node`
   и ростом `tup_returned` на реплике на 150 млн строк за 30 запросов.
5. Replication lag пойман без искусственных задержек: 44 % чтений сразу
   после записи вернули устаревшее значение.

**Чего эта схема не даёт.**

Реплика не ускоряет отдельный запрос и не отменяет необходимость
индексов. Она не является второй базой для записи. И она вносит новый
класс ошибок, которых в однобазовой системе не было: «пользователь
изменил профиль и не увидел изменений». Лечится это не настройками
СУБД, а решением на уровне кода — какое чтение переживёт отставание,
а какое нет.

**Что стоит доделать за пределами лабораторной.**

Пул реплик с балансировщиком (HAProxy или PgBouncer) вместо одной строки
подключения; мониторинг отставания и размера слота — отставший standby
заставляет Primary копить WAL и способен заполнить ему диск; процедура
failover с выбором новой Primary.

---

## Состав работы

| Файл | Что внутри |
|---|---|
| [`infra/docker-compose.replica.yml`](infra/docker-compose.replica.yml) | Часть 1: фрагмент compose с двумя PostgreSQL |
| [`infra/01-prepare-primary.sh`](infra/01-prepare-primary.sh) | Часть 2: роль, слот, правило `pg_hba.conf` |
| [`infra/02-basebackup-replica.sh`](infra/02-basebackup-replica.sh) | Часть 2: `pg_basebackup` и разбор его флагов |
| [`infra/03-proof-replication.sh`](infra/03-proof-replication.sh) | Части 3–4: доказательство репликации и read-only |
| [`infra/04-replication-lag.sh`](infra/04-replication-lag.sh) | Часть 6: три опыта с отставанием |
| [`infra/05-service-reads-on-replica.sh`](infra/05-service-reads-on-replica.sh) | Часть 5: чтение сервиса через Replica |
| [`infra/06-lag-through-api.py`](infra/06-lag-through-api.py) | Часть 6: статистика устаревших чтений через API |
| [`sql/replication-monitoring.sql`](sql/replication-monitoring.sql) | Запросы наблюдения с обеих сторон |
| [`code/`](code) | `IDbConnectionFactory`, `DbConnectionFactory`, `ReplicationController` |
| [`raw/`](raw) | Сырой вывод всех прогонов |
