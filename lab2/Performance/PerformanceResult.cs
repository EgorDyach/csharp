namespace lab2.Performance;

public class PerformanceResult
{
    public string OperationName { get; set; } = string.Empty;
    public string CollectionType { get; set; } = string.Empty;
    public long AverageTimeMs { get; set; }
    public long MinTimeMs { get; set; }
    public long MaxTimeMs { get; set; }
    public int Iterations { get; set; }
}

