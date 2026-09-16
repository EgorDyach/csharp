using System.Net;
using System.Net.Mail;
using System.Text;
using System.Text.Json;
using Microsoft.Extensions.Options;

namespace ChakChakShop.API.Services.Partitioning;

/// <summary>
/// Канал по умолчанию. Пишет в Serilog, поэтому alert виден в логах сервиса
/// и в файле logs/chakchakshop-*.txt даже если внешний канал не настроен.
/// </summary>
public class LogAlertNotifier : IPartitionAlertNotifier
{
    private readonly ILogger<LogAlertNotifier> _logger;

    public LogAlertNotifier(ILogger<LogAlertNotifier> logger) => _logger = logger;

    public string Channel => "log";

    public Task SendAsync(AlertSeverity severity, string subject, string message,
        CancellationToken cancellationToken = default)
    {
        if (severity == AlertSeverity.Critical)
        {
            _logger.LogCritical("PARTITION ALERT {Subject}\n{Message}", subject, message);
        }
        else
        {
            _logger.LogInformation("PARTITION RECOVERY {Subject}\n{Message}", subject, message);
        }

        return Task.CompletedTask;
    }
}

/// <summary>
/// Универсальный webhook: VK, MAX, Telegram, Slack и Mattermost принимают
/// POST с JSON-телом, отличается только имя поля с текстом и набор
/// служебных полей (chat_id, peer_id, access_token). И то и другое задаётся
/// конфигурацией, поэтому канал меняется без правки кода.
/// </summary>
public class WebhookAlertNotifier : IPartitionAlertNotifier
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly AlertOptions _options;
    private readonly ILogger<WebhookAlertNotifier> _logger;

    public WebhookAlertNotifier(
        IHttpClientFactory httpClientFactory,
        IOptions<PartitionOptions> options,
        ILogger<WebhookAlertNotifier> logger)
    {
        _httpClientFactory = httpClientFactory;
        _options = options.Value.Alerts;
        _logger = logger;
    }

    public string Channel => "webhook";

    public async Task SendAsync(AlertSeverity severity, string subject, string message,
        CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(_options.WebhookUrl))
        {
            return;
        }

        var payload = new Dictionary<string, string>(_options.WebhookExtraFields)
        {
            [_options.WebhookTextField] = message
        };

        using var client = _httpClientFactory.CreateClient(nameof(WebhookAlertNotifier));
        using var content = new StringContent(
            JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");

        try
        {
            var response = await client.PostAsync(_options.WebhookUrl, content, cancellationToken);
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Webhook alert rejected with {StatusCode}", response.StatusCode);
            }
        }
        catch (Exception ex)
        {
            // Падение канала уведомлений не должно ронять проверку:
            // авария всё равно уже записана в лог LogAlertNotifier'ом.
            _logger.LogError(ex, "Webhook alert delivery failed");
        }
    }
}

public class EmailAlertNotifier : IPartitionAlertNotifier
{
    private readonly EmailAlertOptions? _options;
    private readonly ILogger<EmailAlertNotifier> _logger;

    public EmailAlertNotifier(IOptions<PartitionOptions> options, ILogger<EmailAlertNotifier> logger)
    {
        _options = options.Value.Alerts.Email;
        _logger = logger;
    }

    public string Channel => "email";

    public async Task SendAsync(AlertSeverity severity, string subject, string message,
        CancellationToken cancellationToken = default)
    {
        if (_options is null || string.IsNullOrWhiteSpace(_options.Host) || _options.To.Count == 0)
        {
            return;
        }

        try
        {
            using var client = new SmtpClient(_options.Host, _options.Port) { EnableSsl = _options.UseSsl };
            if (!string.IsNullOrEmpty(_options.Username))
            {
                client.Credentials = new NetworkCredential(_options.Username, _options.Password);
            }

            using var mail = new MailMessage { From = new MailAddress(_options.From), Subject = subject, Body = message };
            foreach (var to in _options.To)
            {
                mail.To.Add(to);
            }

            await client.SendMailAsync(mail, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Email alert delivery failed");
        }
    }
}
