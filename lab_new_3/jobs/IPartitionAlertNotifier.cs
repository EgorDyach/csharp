namespace ChakChakShop.API.Services.Partitioning;

public enum AlertSeverity
{
    Critical,
    Recovery
}

public interface IPartitionAlertNotifier
{
    string Channel { get; }

    Task SendAsync(AlertSeverity severity, string subject, string message, CancellationToken cancellationToken = default);
}
