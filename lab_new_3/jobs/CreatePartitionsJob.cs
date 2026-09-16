using System.Text;
using Microsoft.Extensions.Options;

namespace ChakChakShop.API.Services.Partitioning;

/// <summary>
/// Ночная job: держит горизонт будущих партиций.
///
///   определить текущий период
///        -> определить требуемый горизонт
///        -> получить существующие партиции
///        -> найти отсутствующие
///        -> создать их
///
/// Повторный запуск безопасен: создание идёт через CREATE TABLE IF NOT EXISTS
/// под advisory-lock, поэтому ни ручной вызов, ни второй экземпляр сервиса
/// ничего не сломают.
/// </summary>
public class CreatePartitionsJob : BackgroundService
{
    /// <summary>Как часто job сверяется с часами. Минута точности здесь более чем достаточна.</summary>
    private static readonly TimeSpan TickInterval = TimeSpan.FromMinutes(1);

    private readonly IPartitionManager _partitionManager;
    private readonly PartitionOptions _options;
    private readonly ILogger<CreatePartitionsJob> _logger;

    public CreatePartitionsJob(
        IPartitionManager partitionManager,
        IOptions<PartitionOptions> options,
        ILogger<CreatePartitionsJob> logger)
    {
        _partitionManager = partitionManager;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            _logger.LogInformation("Partition automation is disabled");
            return;
        }

        // Один прогон на старте: если сервис поднимают после простоя,
        // горизонт должен восстановиться сразу, а не в час ночи.
        await RunOnceAsync(stoppingToken);

        // Расписание держится на сравнении с часами, а не на одном длинном
        // Task.Delay до часа ночи. Длинное ожидание переживает не всякую паузу:
        // если хост уснул, монотонный таймер внутри контейнера встаёт вместе
        // с ним, и запуск не происходит вовсе — проверено на живом стенде,
        // где job молчала целые сутки, а о пропаже партиции сообщил
        // PartitionHealthCheck. Короткий тик переживает засыпание и навёрстывает
        // пропущенный запуск при первом же пробуждении.
        var nextRun = NextRunAfter(DateTime.UtcNow);
        _logger.LogInformation("Next partition job run at {NextRun:u}", nextRun);

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                await Task.Delay(TickInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }

            if (DateTime.UtcNow < nextRun)
            {
                continue;
            }

            await RunOnceAsync(stoppingToken);

            nextRun = NextRunAfter(DateTime.UtcNow);
            _logger.LogInformation("Next partition job run at {NextRun:u}", nextRun);
        }
    }

    private async Task RunOnceAsync(CancellationToken cancellationToken)
    {
        try
        {
            var report = await _partitionManager.EnsurePartitionsAsync(cancellationToken);

            // Отчёт печатается одним блоком: на защите его читают целиком,
            // а не собирают из разбросанных по логу строк.
            var log = new StringBuilder();
            log.AppendLine("Partition job started.").AppendLine();
            log.AppendLine($"Existing partitions: {report.ExistingCount}");
            log.AppendLine($"Required partitions: {report.RequiredCount}");
            log.AppendLine($"Missing partitions: {report.MissingCount}");

            if (report.Created.Count > 0)
            {
                log.AppendLine().AppendLine("Creating:");
                foreach (var created in report.Created)
                {
                    log.AppendLine($"{created.Partition}  [{created.From:yyyy-MM-dd} .. {created.To:yyyy-MM-dd})");
                }

                log.AppendLine().AppendLine("Partition created successfully.");
            }

            foreach (var error in report.Errors)
            {
                log.AppendLine().AppendLine($"FAILED: {error}");
            }

            log.AppendLine().AppendLine(
                $"Partition job finished in {(report.FinishedAt - report.StartedAt).TotalMilliseconds:F0} ms.");

            if (report.Success)
            {
                _logger.LogInformation("{Report}", log.ToString());
            }
            else
            {
                _logger.LogError("{Report}", log.ToString());
            }

        }
        catch (Exception ex)
        {
            // Упавшая job не должна ронять сервис: о проблеме всё равно
            // сообщит PartitionHealthCheck, когда горизонт кончится.
            _logger.LogError(ex, "Partition job crashed");
        }
    }

    /// <summary>Ближайший наступающий момент запуска строго после <paramref name="now"/>.</summary>
    private DateTime NextRunAfter(DateTime now)
    {
        var next = now.Date + _options.CreateJobTimeOfDay;
        return next <= now ? next.AddDays(1) : next;
    }
}
