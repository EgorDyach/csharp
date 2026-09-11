using Dapper;
using Microsoft.Extensions.Options;
using Npgsql;

namespace ChakChakShop.API.Services.Partitioning;

public class PartitionManager : IPartitionManager
{
    // Ключ advisory-lock: два экземпляра сервиса не должны создавать
    // одну и ту же партицию одновременно — второй получит отказ блокировки
    // и просто пропустит запуск.
    private const long AdvisoryLockKey = 741_852_963;

    private readonly string _connectionString;
    private readonly PartitionOptions _options;
    private readonly ILogger<PartitionManager> _logger;

    public PartitionManager(
        IConfiguration configuration,
        IOptions<PartitionOptions> options,
        ILogger<PartitionManager> logger)
    {
        _connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
        _options = options.Value;
        _logger = logger;
    }

    public async Task<IReadOnlyList<PartitionDescriptor>> GetPartitionsAsync(
        PartitionedTableOptions table, CancellationToken cancellationToken = default)
    {
        const string sql = @"
            SELECT c.relname                          AS name,
                   pg_get_expr(c.relpartbound, c.oid) AS bounds,
                   pg_total_relation_size(c.oid)      AS sizebytes
            FROM pg_class c
            JOIN pg_inherits i  ON i.inhrelid = c.oid
            JOIN pg_class p     ON p.oid = i.inhparent
            JOIN pg_namespace n ON n.oid = p.relnamespace
            WHERE n.nspname = @Schema AND p.relname = @Table
            ORDER BY c.relname";

        await using var connection = new NpgsqlConnection(_connectionString);
        var rows = await connection.QueryAsync<PartitionDescriptor>(
            new CommandDefinition(sql, new { table.Schema, table.Table }, cancellationToken: cancellationToken));
        return rows.ToList();
    }

    public async Task<PartitionJobReport> EnsurePartitionsAsync(CancellationToken cancellationToken = default)
    {
        var startedAt = DateTime.UtcNow;
        var created = new List<PartitionCreationResult>();
        var errors = new List<string>();
        var existingTotal = 0;
        var requiredTotal = 0;
        var missingTotal = 0;

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.OpenAsync(cancellationToken);

        var lockAcquired = await connection.ExecuteScalarAsync<bool>(
            new CommandDefinition("SELECT pg_try_advisory_lock(@Key)",
                new { Key = AdvisoryLockKey }, cancellationToken: cancellationToken));

        if (!lockAcquired)
        {
            _logger.LogInformation(
                "Partition job skipped: another instance holds the advisory lock");
            return new PartitionJobReport(startedAt, DateTime.UtcNow, 0, 0, 0, created, errors);
        }

        try
        {
            foreach (var table in _options.Tables)
            {
                var existing = (await GetPartitionsAsync(table, cancellationToken))
                    .Select(p => p.Name)
                    .ToHashSet(StringComparer.Ordinal);
                existingTotal += existing.Count;

                foreach (var periodStart in table.RequiredPeriods(DateTime.UtcNow))
                {
                    requiredTotal++;
                    var name = table.PartitionName(periodStart);
                    if (existing.Contains(name))
                    {
                        continue;
                    }

                    missingTotal++;
                    var periodEnd = table.Next(periodStart);
                    try
                    {
                        await CreatePartitionAsync(connection, table, name, periodStart, periodEnd, cancellationToken);
                        created.Add(new PartitionCreationResult(table.QualifiedName, name, periodStart, periodEnd, true));
                        _logger.LogDebug("Created partition {Partition} for {Table} [{From:u} .. {To:u})",
                            name, table.QualifiedName, periodStart, periodEnd);
                    }
                    catch (Exception ex)
                    {
                        // Типичная причина: в DEFAULT-партиции уже лежат строки
                        // из этого диапазона, и PostgreSQL не может её сузить.
                        errors.Add($"{table.QualifiedName}/{name}: {ex.Message}");
                        _logger.LogError(ex, "Failed to create partition {Partition} for {Table}",
                            name, table.QualifiedName);
                    }
                }
            }
        }
        finally
        {
            await connection.ExecuteAsync(
                new CommandDefinition("SELECT pg_advisory_unlock(@Key)",
                    new { Key = AdvisoryLockKey }, cancellationToken: cancellationToken));
        }

        return new PartitionJobReport(
            startedAt, DateTime.UtcNow, existingTotal, requiredTotal, missingTotal, created, errors);
    }

    public async Task<PartitionHealthReport> CheckHealthAsync(CancellationToken cancellationToken = default)
    {
        var now = DateTime.UtcNow;
        var tables = new List<TablePartitionHealth>();

        foreach (var table in _options.Tables)
        {
            var existing = (await GetPartitionsAsync(table, cancellationToken))
                .Select(p => p.Name)
                .ToHashSet(StringComparer.Ordinal);

            var expected = table.RequiredPeriods(now).Select(table.PartitionName).ToList();
            var missing = expected.Where(name => !existing.Contains(name)).ToList();

            tables.Add(new TablePartitionHealth(table.QualifiedName, table.HorizonPeriods, expected, missing));
        }

        return new PartitionHealthReport(now, tables);
    }

    public async Task DropFuturePartitionAsync(
        string table, string partition, CancellationToken cancellationToken = default)
    {
        var options = _options.Tables.FirstOrDefault(t =>
                          string.Equals(t.QualifiedName, table, StringComparison.OrdinalIgnoreCase) ||
                          string.Equals(t.Table, table, StringComparison.OrdinalIgnoreCase))
                      ?? throw new InvalidOperationException($"Table '{table}' is not managed by the partition job.");

        var known = await GetPartitionsAsync(options, cancellationToken);
        var target = known.FirstOrDefault(p => string.Equals(p.Name, partition, StringComparison.Ordinal))
                     ?? throw new InvalidOperationException($"Partition '{partition}' not found in {options.QualifiedName}.");

        // Учебная авария воспроизводится только на будущих (заведомо пустых)
        // партициях: удалить исторические данные этим методом нельзя.
        var currentPeriodName = options.PartitionName(options.Truncate(DateTime.UtcNow));
        if (string.CompareOrdinal(target.Name, currentPeriodName) <= 0)
        {
            throw new InvalidOperationException(
                $"Refusing to drop '{partition}': only future partitions (after '{currentPeriodName}') may be dropped.");
        }

        await using var connection = new NpgsqlConnection(_connectionString);
        var sql = $"DROP TABLE {Quote(options.Schema)}.{Quote(target.Name)}";
        await connection.ExecuteAsync(new CommandDefinition(sql, cancellationToken: cancellationToken));
        _logger.LogWarning("Partition {Partition} of {Table} dropped on purpose (failure simulation)",
            target.Name, options.QualifiedName);
    }

    private static async Task CreatePartitionAsync(
        NpgsqlConnection connection,
        PartitionedTableOptions table,
        string partitionName,
        DateTime from,
        DateTime to,
        CancellationToken cancellationToken)
    {
        // IF NOT EXISTS делает запуск идемпотентным даже в гонке с другим
        // экземпляром, который успел создать партицию между проверкой и вставкой.
        var sql = $@"
            CREATE TABLE IF NOT EXISTS {Quote(table.Schema)}.{Quote(partitionName)}
            PARTITION OF {Quote(table.Schema)}.{Quote(table.Table)}
            FOR VALUES FROM ('{from:yyyy-MM-dd HH:mm:ss}') TO ('{to:yyyy-MM-dd HH:mm:ss}')";

        await connection.ExecuteAsync(new CommandDefinition(sql, cancellationToken: cancellationToken));
    }

    private static string Quote(string identifier) => "\"" + identifier.Replace("\"", "\"\"") + "\"";
}
