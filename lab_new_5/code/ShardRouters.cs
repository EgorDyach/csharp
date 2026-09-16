namespace ChakChakShop.API.Data.Sharding;

/// <summary>
/// Роутер: по ключу шардирования говорит, на каком узле лежит запись.
/// Ничего больше он не делает и ничего не знает про SQL.
/// </summary>
public interface IShardRouter
{
    string Name { get; }

    int ShardCount { get; }

    int ResolveShard(string shardKey);

    int ResolveShard(Guid shardKey) => ResolveShard(shardKey.ToString());
}

/// <summary>
/// Стратегия 1: hash(key) % N.
///
/// Раскладывает ключи максимально ровно, но намертво привязана к N:
/// при смене количества узлов остаток меняется почти у всех ключей.
/// Насколько именно — измерено в части 5.
/// </summary>
public class ModuloShardRouter : IShardRouter
{
    public ModuloShardRouter(int shardCount)
    {
        if (shardCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(shardCount), "Количество шардов должно быть положительным.");
        }

        ShardCount = shardCount;
    }

    public string Name => "modulo";

    public int ShardCount { get; }

    public int ResolveShard(string shardKey) => (int)(ShardHash.Compute(shardKey) % ShardCount);
}

/// <summary>
/// Стратегия 2: consistent hashing.
///
/// Узлы и ключи кладутся на одно кольцо; ключ обслуживает первый узел
/// по часовой стрелке. При добавлении узла переезжает только тот участок
/// кольца, который новый узел у соседа отрезал, — остальные ключи
/// остаются на месте.
///
/// Виртуальные узлы обязательны. Три точки, разбросанные хеш-функцией
/// по кольцу, лягут как попало, и один шард заберёт половину диапазона.
/// 256 точек на шард сглаживают это до единиц процентов.
/// </summary>
public class ConsistentHashRouter : IShardRouter
{
    private readonly long[] _positions;      // отсортированные точки кольца
    private readonly int[] _owners;          // какому шарду принадлежит точка
    private readonly int _virtualNodes;

    public ConsistentHashRouter(int shardCount, int virtualNodes = 256)
    {
        if (shardCount <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(shardCount), "Количество шардов должно быть положительным.");
        }

        ShardCount = shardCount;
        _virtualNodes = virtualNodes;

        // Имя виртуального узла собирается ровно так же, как в SQL:
        // 'shard-<id>#<n>'. Иначе кольца в сервисе и в аналитике разойдутся.
        var ring = new List<(long Position, int Shard)>(shardCount * virtualNodes);
        for (var shard = 0; shard < shardCount; shard++)
        {
            for (var vnode = 0; vnode < virtualNodes; vnode++)
            {
                ring.Add((ShardHash.Compute($"shard-{shard}#{vnode}"), shard));
            }
        }

        ring.Sort((a, b) => a.Position.CompareTo(b.Position));

        _positions = ring.Select(p => p.Position).ToArray();
        _owners = ring.Select(p => p.Shard).ToArray();
    }

    public string Name => $"consistent-hashing(vnodes={_virtualNodes})";

    public int ShardCount { get; }

    public int ResolveShard(string shardKey)
    {
        var hash = ShardHash.Compute(shardKey);

        // Первая точка кольца справа от ключа. BinarySearch на промахе
        // возвращает дополнение индекса вставки — это и есть нужная точка.
        var index = Array.BinarySearch(_positions, hash);
        if (index < 0)
        {
            index = ~index;
        }

        // Ключ правее последней точки — кольцо замыкается на первую.
        if (index >= _positions.Length)
        {
            index = 0;
        }

        return _owners[index];
    }

    /// <summary>Доля кольца, приходящаяся на каждый шард. Для диагностики перекоса.</summary>
    public IReadOnlyDictionary<int, double> RingShare()
    {
        var share = new double[ShardCount];
        for (var i = 0; i < _positions.Length; i++)
        {
            var from = i == 0 ? _positions[^1] - (1L << 60) : _positions[i - 1];
            share[_owners[i]] += _positions[i] - from;
        }

        var total = share.Sum();
        return Enumerable.Range(0, ShardCount).ToDictionary(s => s, s => 100.0 * share[s] / total);
    }
}
