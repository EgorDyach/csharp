using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Options;
using ChakChakShop.API.Services.Partitioning;

namespace ChakChakShop.API.Controllers;

/// <summary>
/// Эксплуатационные ручки партиционирования: посмотреть состояние,
/// досоздать партиции, воспроизвести аварию на защите.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(AuthenticationSchemes = $"ApiKey,{JwtBearerDefaults.AuthenticationScheme}", Roles = "ApiKey,Admin")]
public class PartitionsController : ControllerBase
{
    private readonly IPartitionManager _partitionManager;
    private readonly IPartitionAlertService _alertService;
    private readonly PartitionOptions _options;

    public PartitionsController(
        IPartitionManager partitionManager,
        IPartitionAlertService alertService,
        IOptions<PartitionOptions> options)
    {
        _partitionManager = partitionManager;
        _alertService = alertService;
        _options = options.Value;
    }

    /// <summary>Список партиций каждой отслеживаемой таблицы.</summary>
    [HttpGet]
    public async Task<IActionResult> List(CancellationToken cancellationToken)
    {
        var result = new List<object>();
        foreach (var table in _options.Tables)
        {
            var partitions = await _partitionManager.GetPartitionsAsync(table, cancellationToken);
            result.Add(new
            {
                table = table.QualifiedName,
                interval = table.Interval.ToString(),
                horizon = table.HorizonPeriods,
                partitions = partitions.Select(p => new { p.Name, p.Bounds, sizeBytes = p.SizeBytes })
            });
        }

        return Ok(result);
    }

    /// <summary>
    /// PartitionHealthCheck: существуют ли все партиции, которые должны
    /// существовать на ближайшие N периодов.
    /// </summary>
    [HttpGet("health")]
    public async Task<IActionResult> Health(CancellationToken cancellationToken)
    {
        var report = await _partitionManager.CheckHealthAsync(cancellationToken);
        var payload = new
        {
            status = report.Status.ToString().ToUpperInvariant(),
            checkedAt = report.CheckedAt.ToString("yyyy-MM-dd HH:mm:ss"),
            tables = report.Tables.Select(t => new
            {
                table = t.Table,
                status = t.Status.ToString().ToUpperInvariant(),
                horizon = t.HorizonPeriods,
                expected = t.ExpectedPartitions,
                missing = t.MissingPartitions
            })
        };

        return report.Status == PartitionHealthStatus.Ok ? Ok(payload) : StatusCode(503, payload);
    }

    /// <summary>Ручной запуск CreatePartitionsJob.</summary>
    [HttpPost("ensure")]
    public async Task<IActionResult> Ensure(CancellationToken cancellationToken)
    {
        var report = await _partitionManager.EnsurePartitionsAsync(cancellationToken);
        return Ok(new
        {
            existing = report.ExistingCount,
            required = report.RequiredCount,
            missing = report.MissingCount,
            created = report.Created.Select(c => c.Partition),
            errors = report.Errors,
            elapsedMs = (report.FinishedAt - report.StartedAt).TotalMilliseconds
        });
    }

    /// <summary>Проверка с рассылкой уведомлений — то же, что делает фоновая проверка.</summary>
    [HttpPost("check")]
    public async Task<IActionResult> Check(CancellationToken cancellationToken)
    {
        var report = await _partitionManager.CheckHealthAsync(cancellationToken);
        var actions = await _alertService.ProcessAsync(report, cancellationToken);
        return Ok(new
        {
            status = report.Status.ToString().ToUpperInvariant(),
            checkedAt = report.CheckedAt.ToString("yyyy-MM-dd HH:mm:ss"),
            actions
        });
    }

    /// <summary>
    /// Учебная авария: удаляет одну будущую партицию, чтобы проверить,
    /// что alert действительно работает. Исторические партиции удалить нельзя.
    /// </summary>
    [HttpDelete("{table}/{partition}")]
    public async Task<IActionResult> SimulateFailure(string table, string partition, CancellationToken cancellationToken)
    {
        try
        {
            await _partitionManager.DropFuturePartitionAsync(table, partition, cancellationToken);
            return Ok(new { dropped = partition });
        }
        catch (InvalidOperationException ex)
        {
            return BadRequest(new { error = ex.Message });
        }
    }
}
