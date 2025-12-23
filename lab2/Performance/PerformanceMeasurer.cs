namespace lab2.Performance;

public static class PerformanceMeasurer
{
    public static List<PerformanceResult> MeasureAll()
    {
        var allResults = new List<PerformanceResult>();
        
        allResults.AddRange(ListPerformance.MeasureAll());
        allResults.AddRange(LinkedListPerformance.MeasureAll());
        allResults.AddRange(QueuePerformance.MeasureAll());
        allResults.AddRange(StackPerformance.MeasureAll());
        allResults.AddRange(ImmutableListPerformance.MeasureAll());
        
        return allResults;
    }
}

