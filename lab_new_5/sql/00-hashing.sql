-- =====================================================================
-- Общая хеш-функция для роутера и для аналитики
-- =====================================================================
-- Роутер живёт в C#, а распределение пяти миллионов строк считается
-- в SQL. Обе стороны обязаны давать ОДИН И ТОТ ЖЕ номер шарда для
-- одного и того же ключа, иначе данные лягут не туда, куда потом
-- пойдёт запрос. Поэтому хеш выбран так, чтобы его можно было
-- воспроизвести в любом языке буква в букву.
--
-- Что нельзя использовать:
--   * GetHashCode() в .NET — не стабилен между запусками процесса;
--   * hashtext() в PostgreSQL — внутренняя функция без гарантий
--     совместимости между версиями.
--
-- Что используется: первые 15 шестнадцатеричных цифр md5 от текстового
-- представления ключа, то есть 60 бит. Пятнадцать, а не шестнадцать,
-- чтобы значение гарантированно оставалось положительным в bigint.
-- MD5 здесь не про криптографию, а про равномерность: ключ шардирования
-- не защищают, его распределяют.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS shardlab;

-- CREATE OR REPLACE не умеет переименовывать параметры, поэтому при
-- повторном прогоне функции сначала сносятся.
DROP FUNCTION IF EXISTS shardlab.shard_by_ring(text, int);
DROP FUNCTION IF EXISTS shardlab.shard_by_modulo(text, int);
DROP FUNCTION IF EXISTS shardlab.build_ring(int, int);
DROP FUNCTION IF EXISTS shardlab.shard_hash(text);

CREATE OR REPLACE FUNCTION shardlab.shard_hash(p_key text)
RETURNS bigint
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT ('x0' || substr(md5(p_key), 1, 15))::bit(64)::bigint;
$$;

COMMENT ON FUNCTION shardlab.shard_hash(text) IS
    '60-битный хеш ключа шардирования. Точная копия ShardHash.Compute() в C#.';

-- Стратегия 1: hash(key) % N
CREATE OR REPLACE FUNCTION shardlab.shard_by_modulo(p_key text, p_shard_count int)
RETURNS int
LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE
AS $$
    SELECT (shardlab.shard_hash(p_key) % p_shard_count)::int;
$$;

-- =====================================================================
-- Стратегия 2: consistent hashing
-- =====================================================================
-- Кольцо — это таблица точек. Каждый шард представлен на нём не одной
-- точкой, а VNODES виртуальными узлами: иначе три случайные точки лягут
-- как попало и один шард заберёт половину кольца.
CREATE TABLE IF NOT EXISTS shardlab.hash_ring (
    shard_count int    NOT NULL,   -- размер кластера, для которого построено кольцо
    position    bigint NOT NULL,
    shard_id    int    NOT NULL,
    vnode       int    NOT NULL,
    PRIMARY KEY (shard_count, position)
);

CREATE OR REPLACE FUNCTION shardlab.build_ring(p_shard_count int, p_vnodes int DEFAULT 256)
RETURNS int
LANGUAGE plpgsql
AS $$
DECLARE
    inserted int;
BEGIN
    DELETE FROM shardlab.hash_ring r WHERE r.shard_count = p_shard_count;

    -- Имя виртуального узла — 'shard-<id>#<n>'. Ровно эта же строка
    -- хешируется в C#, поэтому кольца совпадают точка в точку.
    INSERT INTO shardlab.hash_ring (shard_count, position, shard_id, vnode)
    SELECT p_shard_count,
           shardlab.shard_hash('shard-' || s || '#' || v),
           s,
           v
    FROM generate_series(0, p_shard_count - 1) s,
         generate_series(0, p_vnodes - 1) v
    ON CONFLICT (shard_count, position) DO NOTHING;

    GET DIAGNOSTICS inserted = ROW_COUNT;
    RETURN inserted;
END $$;

-- Поиск шарда по кольцу: первая точка по часовой стрелке, а если
-- ключ оказался правее последней точки — кольцо замыкается на первую.
CREATE OR REPLACE FUNCTION shardlab.shard_by_ring(p_key text, p_shard_count int)
RETURNS int
LANGUAGE sql STABLE STRICT PARALLEL SAFE
AS $$
    SELECT COALESCE(
        (SELECT r.shard_id FROM shardlab.hash_ring r
          WHERE r.shard_count = p_shard_count
            AND r.position >= shardlab.shard_hash(p_key)
          ORDER BY r.position LIMIT 1),
        (SELECT r.shard_id FROM shardlab.hash_ring r
          WHERE r.shard_count = p_shard_count
          ORDER BY r.position LIMIT 1)
    );
$$;
