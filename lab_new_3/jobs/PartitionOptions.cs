namespace ChakChakShop.API.Services.Partitioning;

/// <summary>
/// Шаг партиционирования. От него зависят и границы партиции,
/// и формат её имени.
/// </summary>
public enum PartitionInterval
{
    Daily,
    Monthly
}

/// <summary>
/// Описание одной партиционированной таблицы, за которой следит сервис.
/// </summary>
public class PartitionedTableOptions
{
    public string Schema { get; set; } = "public";

    /// <summary>Имя родительской (партиционированной) таблицы.</summary>
    public string Table { get; set; } = string.Empty;

    public PartitionInterval Interval { get; set; } = PartitionInterval.Monthly;

    /// <summary>
    /// Префикс имени партиции. Полное имя получается как
    /// <c>NamePrefix + дата в формате шага</c>, например <c>orders_p_2026_10</c>.
    /// </summary>
    public string NamePrefix { get; set; } = string.Empty;

    /// <summary>
    /// На сколько периодов вперёд партиции должны существовать всегда.
    /// Горизонт 3 для дневного шага означает «сегодня плюс три дня».
    /// </summary>
    public int HorizonPeriods { get; set; } = 3;

    public string QualifiedName => $"{Schema}.{Table}";

    /// <summary>Формат даты в имени партиции.</summary>
    public string NameFormat => Interval == PartitionInterval.Daily ? "yyyy_MM_dd" : "yyyy_MM";

    /// <summary>Начало периода, в который попадает указанный момент времени.</summary>
    public DateTime Truncate(DateTime moment) => Interval == PartitionInterval.Daily
        ? moment.Date
        : new DateTime(moment.Year, moment.Month, 1, 0, 0, 0, moment.Kind);

    public DateTime Next(DateTime periodStart) => Interval == PartitionInterval.Daily
        ? periodStart.AddDays(1)
        : periodStart.AddMonths(1);

    public string PartitionName(DateTime periodStart) =>
        NamePrefix + periodStart.ToString(NameFormat);

    /// <summary>
    /// Периоды, партиции для которых обязаны существовать прямо сейчас:
    /// текущий плюс <see cref="HorizonPeriods"/> следующих.
    /// </summary>
    public IEnumerable<DateTime> RequiredPeriods(DateTime now)
    {
        var period = Truncate(now);
        for (var i = 0; i <= HorizonPeriods; i++)
        {
            yield return period;
            period = Next(period);
        }
    }
}

public class PartitionOptions
{
    public const string SectionName = "Partitioning";

    /// <summary>Выключатель на случай, если сервис поднимают на непартиционированной базе.</summary>
    public bool Enabled { get; set; } = true;

    /// <summary>Время суток, когда запускается CreatePartitionsJob.</summary>
    public TimeSpan CreateJobTimeOfDay { get; set; } = new(1, 0, 0);

    /// <summary>Как часто PartitionHealthCheck перепроверяет состояние.</summary>
    public TimeSpan HealthCheckInterval { get; set; } = TimeSpan.FromMinutes(5);

    /// <summary>
    /// Как долго молчать, если проблема уже известна. Повторный alert уходит
    /// только по истечении этого срока — иначе канал завалит одинаковыми
    /// сообщениями каждые пять минут.
    /// </summary>
    public TimeSpan RenotifyAfter { get; set; } = TimeSpan.FromHours(6);

    public List<PartitionedTableOptions> Tables { get; set; } = new();

    public AlertOptions Alerts { get; set; } = new();
}

public class AlertOptions
{
    /// <summary>
    /// HTTP-канал уведомлений. Подходит для VK Callback API, MAX, Telegram,
    /// Slack и любого другого webhook: тело запроса — JSON вида
    /// <c>{ "text": "..." }</c>.
    /// </summary>
    public string? WebhookUrl { get; set; }

    /// <summary>Имя поля с текстом сообщения в теле webhook-запроса.</summary>
    public string WebhookTextField { get; set; } = "text";

    /// <summary>Дополнительные поля тела запроса (chat_id, peer_id, access_token и т. п.).</summary>
    public Dictionary<string, string> WebhookExtraFields { get; set; } = new();

    public EmailAlertOptions? Email { get; set; }
}

public class EmailAlertOptions
{
    public string Host { get; set; } = string.Empty;
    public int Port { get; set; } = 587;
    public bool UseSsl { get; set; } = true;
    public string? Username { get; set; }
    public string? Password { get; set; }
    public string From { get; set; } = string.Empty;
    public List<string> To { get; set; } = new();
}
