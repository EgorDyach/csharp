using Microsoft.Extensions.Options;

namespace ChakChakShop.API.Services.Partitioning;

/// <summary>
/// Периодическая проверка горизонта партиций.
///
/// Смысл проверки в том, чтобы узнать о проблеме раньше приложения:
/// если ночная job не отработала, INSERT начнёт падать только когда
/// закончится последняя партиция. Проверка видит это за три периода до аварии.
/// </summary>
public class PartitionHealthCheckJob : BackgroundService
{
    private readonly IPartitionManager _partitionManager;
    private readonly IPartitionAlertService _alertService;
    private readonly PartitionOptions _options;
    private readonly ILogger<PartitionHealthCheckJob> _logger;

    public PartitionHealthCheckJob(
        IPartitionManager partitionManager,
        IPartitionAlertService alertService,
        IOptions<PartitionOptions> options,
        ILogger<PartitionHealthCheckJob> logger)
    {
        _partitionManager = partitionManager;
        _alertService = alertService;
        _options = options.Value;
        _logger = logger;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if (!_options.Enabled)
        {
            return;
        }

        // Небольшая задержка на старте: даём CreatePartitionsJob отработать
        // первым, иначе на свежей базе проверка отправит ложный alert.
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(15), stoppingToken);
        }
        catch (OperationCanceledException)
        {
            return;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            try
            {
                var report = await _partitionManager.CheckHealthAsync(stoppingToken);
                var actions = await _alertService.ProcessAsync(report, stoppingToken);

                _logger.LogInformation("Partition health check: {Status} ({Actions})",
                    report.Status, string.Join("; ", actions));
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Partition health check failed");
            }

            try
            {
                await Task.Delay(_options.HealthCheckInterval, stoppingToken);
            }
            catch (OperationCanceledException)
            {
                return;
            }
        }
    }
}
