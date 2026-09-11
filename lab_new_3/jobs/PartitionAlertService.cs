using System.Text;
using Dapper;
using Microsoft.Extensions.Options;
using Npgsql;

namespace ChakChakShop.API.Services.Partitioning;

/// <summary>
/// Превращает результат проверки в уведомления и следит за тем, чтобы один
/// и тот же alert не уходил бесконечно.
///
/// Состояние хранится в таблице partition_alert_state, а не в памяти:
/// перезапуск сервиса не должен приводить к повторной рассылке уже
/// отправленного alert'а, а несколько экземпляров сервиса должны видеть
/// общую картину.
/// </summary>
public interface IPartitionAlertService
{
    Task<IReadOnlyList<string>> ProcessAsync(PartitionHealthReport report, CancellationToken cancellationToken = default);
}

public class PartitionAlertService : IPartitionAlertService
{
    private readonly string _connectionString;
    private readonly PartitionOptions _options;
    private readonly IEnumerable<IPartitionAlertNotifier> _notifiers;
    private readonly ILogger<PartitionAlertService> _logger;

    public PartitionAlertService(
        IConfiguration configuration,
        IOptions<PartitionOptions> options,
        IEnumerable<IPartitionAlertNotifier> notifiers,
        ILogger<PartitionAlertService> logger)
    {
        _connectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");
        _options = options.Value;
        _notifiers = notifiers;
        _logger = logger;
    }

    public async Task<IReadOnlyList<string>> ProcessAsync(
        PartitionHealthReport report, CancellationToken cancellationToken = default)
    {
        var actions = new List<string>();

        foreach (var table in report.Tables)
        {
            var key = $"partitions:{table.Table}";
            var state = await LoadStateAsync(key, cancellationToken);
            var now = report.CheckedAt;

            if (table.Status == PartitionHealthStatus.Critical)
            {
                var isNewProblem = state is null || state.Status != nameof(PartitionHealthStatus.Critical);
                var quietPeriodOver = state?.LastNotifiedAt is not null &&
                                      now - state.LastNotifiedAt.Value >= _options.RenotifyAfter;

                if (isNewProblem || quietPeriodOver)
                {
                    await NotifyAsync(AlertSeverity.Critical,
                        $"🚨 Partition alert: {table.Table}",
                        BuildCriticalMessage(table, now, isNewProblem ? 1 : (state?.NotifyCount ?? 0) + 1),
                        cancellationToken);

                    await SaveStateAsync(key, nameof(PartitionHealthStatus.Critical),
                        string.Join(",", table.MissingPartitions), now,
                        notified: true,
                        firstSeenAt: isNewProblem ? now : state!.FirstSeenAt,
                        notifyCount: isNewProblem ? 1 : (state?.NotifyCount ?? 0) + 1,
                        cancellationToken);

                    actions.Add($"{table.Table}: alert sent");
                }
                else
                {
                    // Проблема известна и уже отправлена — молчим до окончания
                    // паузы. Именно это отличает alerting от логирования:
                    // лог пишется каждый раз, уведомление — только на смену состояния.
                    await SaveStateAsync(key, nameof(PartitionHealthStatus.Critical),
                        string.Join(",", table.MissingPartitions), now,
                        notified: false,
                        firstSeenAt: state?.FirstSeenAt ?? now,
                        notifyCount: state?.NotifyCount ?? 1,
                        cancellationToken);

                    _logger.LogWarning(
                        "Partitions still missing for {Table}: {Missing}. Alert suppressed (already notified at {At:u})",
                        table.Table, string.Join(", ", table.MissingPartitions), state?.LastNotifiedAt);

                    actions.Add($"{table.Table}: alert suppressed");
                }
            }
            else
            {
                var wasCritical = state is not null && state.Status == nameof(PartitionHealthStatus.Critical);

                if (wasCritical)
                {
                    await NotifyAsync(AlertSeverity.Recovery,
                        $"🟢 Partition check OK: {table.Table}",
                        BuildRecoveryMessage(table, now, state!.FirstSeenAt),
                        cancellationToken);
                    actions.Add($"{table.Table}: recovery sent");
                }
                else
                {
                    actions.Add($"{table.Table}: ok");
                }

                await SaveStateAsync(key, nameof(PartitionHealthStatus.Ok), null, now,
                    notified: wasCritical, firstSeenAt: now, notifyCount: 0, cancellationToken);
            }
        }

        return actions;
    }

    private async Task NotifyAsync(AlertSeverity severity, string subject, string message,
        CancellationToken cancellationToken)
    {
        foreach (var notifier in _notifiers)
        {
            await notifier.SendAsync(severity, subject, message, cancellationToken);
        }
    }

    private string BuildCriticalMessage(TablePartitionHealth table, DateTime checkedAt, int attempt)
    {
        var horizonUnit = table.Table.Contains("events", StringComparison.OrdinalIgnoreCase) ? "days" : "months";
        var sb = new StringBuilder();
        sb.AppendLine("🚨 Partition alert").AppendLine();
        sb.AppendLine($"Table: {table.Table}");
        sb.AppendLine("Missing partitions:");
        foreach (var missing in table.MissingPartitions)
        {
            sb.AppendLine(missing);
        }

        sb.AppendLine();
        sb.AppendLine($"Expected horizon: {table.HorizonPeriods} {horizonUnit}");
        sb.AppendLine();
        sb.AppendLine("Checked at:");
        sb.AppendLine(checkedAt.ToString("yyyy-MM-dd HH:mm:ss"));
        if (attempt > 1)
        {
            sb.AppendLine();
            sb.AppendLine($"(reminder #{attempt}, problem is not resolved yet)");
        }

        return sb.ToString();
    }

    private static string BuildRecoveryMessage(TablePartitionHealth table, DateTime checkedAt, DateTime brokenSince)
    {
        var sb = new StringBuilder();
        sb.AppendLine("🟢 Partition check OK").AppendLine();
        sb.AppendLine($"Table: {table.Table}").AppendLine();
        sb.AppendLine("All required partitions exist.");
        sb.AppendLine($"Downtime: {(checkedAt - brokenSince).TotalMinutes:F1} min");
        sb.AppendLine();
        sb.AppendLine("Checked at:");
        sb.AppendLine(checkedAt.ToString("yyyy-MM-dd HH:mm:ss"));
        return sb.ToString();
    }

    private async Task<AlertState?> LoadStateAsync(string key, CancellationToken cancellationToken)
    {
        const string sql = @"
            SELECT alert_key        AS AlertKey,
                   status           AS Status,
                   details          AS Details,
                   first_seen_at    AS FirstSeenAt,
                   last_notified_at AS LastNotifiedAt,
                   notify_count     AS NotifyCount
            FROM partition_alert_state
            WHERE alert_key = @Key";

        await using var connection = new NpgsqlConnection(_connectionString);
        return await connection.QuerySingleOrDefaultAsync<AlertState>(
            new CommandDefinition(sql, new { Key = key }, cancellationToken: cancellationToken));
    }

    private async Task SaveStateAsync(
        string key, string status, string? details, DateTime checkedAt,
        bool notified, DateTime firstSeenAt, int notifyCount, CancellationToken cancellationToken)
    {
        const string sql = @"
            INSERT INTO partition_alert_state
                (alert_key, status, details, first_seen_at, last_notified_at, notify_count, updated_at)
            VALUES
                (@Key, @Status, @Details, @FirstSeenAt,
                 CASE WHEN @Notified THEN @CheckedAt ELSE NULL END, @NotifyCount, @CheckedAt)
            ON CONFLICT (alert_key) DO UPDATE SET
                status           = EXCLUDED.status,
                details          = EXCLUDED.details,
                first_seen_at    = EXCLUDED.first_seen_at,
                last_notified_at = COALESCE(EXCLUDED.last_notified_at, partition_alert_state.last_notified_at),
                notify_count     = EXCLUDED.notify_count,
                updated_at       = EXCLUDED.updated_at";

        await using var connection = new NpgsqlConnection(_connectionString);
        await connection.ExecuteAsync(new CommandDefinition(sql, new
        {
            Key = key,
            Status = status,
            Details = details,
            FirstSeenAt = firstSeenAt,
            CheckedAt = checkedAt,
            Notified = notified,
            NotifyCount = notifyCount
        }, cancellationToken: cancellationToken));
    }

    private sealed class AlertState
    {
        public string AlertKey { get; set; } = string.Empty;
        public string Status { get; set; } = string.Empty;
        public string? Details { get; set; }
        public DateTime FirstSeenAt { get; set; }
        public DateTime? LastNotifiedAt { get; set; }
        public int NotifyCount { get; set; }
    }
}
