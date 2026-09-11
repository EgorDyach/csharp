namespace ChakChakShop.API.Services.Partitioning;

/// <summary>Существующая партиция и её границы.</summary>
public record PartitionDescriptor(string Name, string Bounds, long SizeBytes);

/// <summary>Одна созданная (или пропущенная) партиция в отчёте job'а.</summary>
public record PartitionCreationResult(string Table, string Partition, DateTime From, DateTime To, bool Created);

public record PartitionJobReport(
    DateTime StartedAt,
    DateTime FinishedAt,
    int ExistingCount,
    int RequiredCount,
    int MissingCount,
    IReadOnlyList<PartitionCreationResult> Created,
    IReadOnlyList<string> Errors)
{
    public bool Success => Errors.Count == 0;
}

public enum PartitionHealthStatus
{
    Ok,
    Critical
}

/// <summary>Состояние одной таблицы: каких партиций не хватает.</summary>
public record TablePartitionHealth(
    string Table,
    int HorizonPeriods,
    IReadOnlyList<string> ExpectedPartitions,
    IReadOnlyList<string> MissingPartitions)
{
    public PartitionHealthStatus Status =>
        MissingPartitions.Count == 0 ? PartitionHealthStatus.Ok : PartitionHealthStatus.Critical;
}

public record PartitionHealthReport(DateTime CheckedAt, IReadOnlyList<TablePartitionHealth> Tables)
{
    public PartitionHealthStatus Status =>
        Tables.Any(t => t.Status == PartitionHealthStatus.Critical)
            ? PartitionHealthStatus.Critical
            : PartitionHealthStatus.Ok;
}
