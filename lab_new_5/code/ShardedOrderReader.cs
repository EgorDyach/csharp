using System.Diagnostics;
using Dapper;
using Microsoft.Extensions.Options;
using Npgsql;

namespace ChakChakShop.API.Data.Sharding;

public record ShardQueryResult<T>(
    IReadOnlyList<T> Rows,
    IReadOnlyList<int> ShardsQueried,
    IReadOnlyList<string> FailedShards,
    double ElapsedMs)
{
    public bool Complete => FailedShards.Count == 0;
}

public record OrderRow(Guid Id, Guid UserId, decimal TotalAmount, string Status, DateTime CreatedAt);

public record ShardCount(int Shard, long Count);

/// <summary>
/// Чтение заказов из шардированного кластера.
///
/// Здесь видна вся разница между двумя классами запросов:
///   * если ключ шардирования известен — работает ОДИН узел;
///   * если неизвестен — приходится опрашивать все и склеивать ответы
///     в приложении, потому что ни один PostgreSQL не видит соседей.
/// </summary>
public class ShardedOrderReader
{
    private readonly ShardOptions _options;
    private readonly IShardRouter _router;
    private readonly ILogger<ShardedOrderReader> _logger;

    public ShardedOrderReader(
        IOptions<ShardOptions> options,
        IShardRouter router,
        ILogger<ShardedOrderReader> logger)
    {
        _options = options.Value;
        _router = router;
        _logger = logger;
    }

    public IShardRouter Router => _router;

    public int ShardCount => _options.Connections.Count;

    private NpgsqlConnection Connect(int shard) => new(_options.Connections[shard]);

    // =================================================================
    // Single-shard query: ключ шардирования есть в условии
    // =================================================================
    public async Task<ShardQueryResult<OrderRow>> GetUserOrdersAsync(
        Guid userId, int limit, CancellationToken cancellationToken = default)
    {
        var shard = _router.ResolveShard(userId);
        var sw = Stopwatch.StartNew();

        const string sql = @"
            SELECT id, user_id AS UserId, total_amount AS TotalAmount, status, created_at AS CreatedAt
            FROM orders
            WHERE user_id = @UserId
            ORDER BY created_at DESC
            LIMIT @Limit";

        await using var connection = Connect(shard);
        var rows = (await connection.QueryAsync<OrderRow>(
            new CommandDefinition(sql, new { UserId = userId, Limit = limit },
                cancellationToken: cancellationToken))).ToList();

        sw.Stop();
        return new ShardQueryResult<OrderRow>(rows, new[] { shard }, Array.Empty<string>(), sw.Elapsed.TotalMilliseconds);
    }

    // =================================================================
    // Scatter-gather: агрегация по всем шардам
    // =================================================================
    public async Task<ShardQueryResult<ShardCount>> CountAllAsync(CancellationToken cancellationToken = default)
    {
        return await ScatterGatherAsync(
            "SELECT count(*) FROM orders",
            async (connection, shard, ct) =>
            {
                var count = await connection.ExecuteScalarAsync<long>(
                    new CommandDefinition("SELECT count(*) FROM orders", cancellationToken: ct));
                return (IReadOnlyList<ShardCount>)new[] { new ShardCount(shard, count) };
            },
            cancellationToken);
    }

    public async Task<ShardQueryResult<OrderRow>> GetNewestAsync(
        int limit, CancellationToken cancellationToken = default)
    {
        // Каждый шард отдаёт свой top-N. Меньше брать нельзя: все N
        // глобально свежих заказов могут оказаться на одном узле.
        var sql = $@"
            SELECT id, user_id AS UserId, total_amount AS TotalAmount, status, created_at AS CreatedAt
            FROM orders ORDER BY created_at DESC LIMIT {limit}";

        var result = await ScatterGatherAsync(
            sql,
            async (connection, shard, ct) =>
            {
                var rows = await connection.QueryAsync<OrderRow>(
                    new CommandDefinition(sql, cancellationToken: ct));
                return (IReadOnlyList<OrderRow>)rows.ToList();
            },
            cancellationToken);

        // Слияние происходит здесь, в приложении: PostgreSQL этого сделать
        // не может — он не видит результаты соседних узлов.
        var merged = result.Rows.OrderByDescending(r => r.CreatedAt).Take(limit).ToList();
        return result with { Rows = merged };
    }

    // =================================================================
    // Общий механизм распределённого запроса
    // =================================================================
    private async Task<ShardQueryResult<T>> ScatterGatherAsync<T>(
        string description,
        Func<NpgsqlConnection, int, CancellationToken, Task<IReadOnlyList<T>>> perShard,
        CancellationToken cancellationToken)
    {
        var sw = Stopwatch.StartNew();
        var queried = new List<int>();
        var failed = new List<string>();
        var rows = new List<T>();

        // Узлы опрашиваются параллельно. Последовательный обход сложил бы
        // задержки шардов, а так общее время равно самому медленному узлу.
        var tasks = Enumerable.Range(0, ShardCount).Select(async shard =>
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(_options.ShardTimeout);

            try
            {
                await using var connection = Connect(shard);
                var shardRows = await perShard(connection, shard, timeout.Token);
                return (Shard: shard, Rows: shardRows, Error: (string?)null);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Shard {Shard} failed on query: {Query}", shard, description);
                return (Shard: shard, Rows: (IReadOnlyList<T>)Array.Empty<T>(), Error: $"shard{shard}: {ex.Message}");
            }
        });

        foreach (var outcome in await Task.WhenAll(tasks))
        {
            if (outcome.Error is null)
            {
                queried.Add(outcome.Shard);
                rows.AddRange(outcome.Rows);
            }
            else
            {
                failed.Add(outcome.Error);
            }
        }

        sw.Stop();

        if (failed.Count > 0 && !_options.AllowPartialResults)
        {
            throw new InvalidOperationException(
                $"Распределённый запрос неполон: недоступны шарды — {string.Join("; ", failed)}");
        }

        return new ShardQueryResult<T>(rows, queried, failed, sw.Elapsed.TotalMilliseconds);
    }

    // =================================================================
    // Локальный JOIN: справочники реплицированы, позиции co-located
    // =================================================================
    public async Task<ShardQueryResult<dynamic>> GetUserOrdersWithItemsAsync(
        Guid userId, int limit, CancellationToken cancellationToken = default)
    {
        var shard = _router.ResolveShard(userId);
        var sw = Stopwatch.StartNew();

        // Все три таблицы лежат на одном узле: orders и order_items —
        // потому что шардированы одним ключом, products — потому что
        // справочник скопирован на каждый шард.
        const string sql = @"
            SELECT o.id AS order_id, o.created_at, o.total_amount,
                   p.name AS product_name, oi.quantity, oi.total_price
            FROM orders o
            JOIN order_items oi ON oi.order_id = o.id AND oi.user_id = o.user_id
            JOIN products p     ON p.id = oi.product_id
            WHERE o.user_id = @UserId
            ORDER BY o.created_at DESC
            LIMIT @Limit";

        await using var connection = Connect(shard);
        var rows = (await connection.QueryAsync(
            new CommandDefinition(sql, new { UserId = userId, Limit = limit },
                cancellationToken: cancellationToken))).ToList();

        sw.Stop();
        return new ShardQueryResult<dynamic>(rows, new[] { shard }, Array.Empty<string>(), sw.Elapsed.TotalMilliseconds);
    }
}
