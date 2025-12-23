using System.Diagnostics;

namespace lab2.Performance;

public static class QueuePerformance
{
    private const int InitialSize = 600_000;

    private static PerformanceResult MeasureOperation(string operationName, Func<Queue<int>> prepareCollection, Action<Queue<int>> operation)
    {
        const int iterations = 15;
        var times = new List<long>();

        for (int i = 0; i < iterations; i++)
        {
            var queue = prepareCollection();
            
            var stopwatch = Stopwatch.StartNew();
            operation(queue);
            stopwatch.Stop();
            times.Add(stopwatch.ElapsedMilliseconds);
        }

        return new PerformanceResult
        {
            OperationName = operationName,
            CollectionType = "Queue",
            AverageTimeMs = (long)times.Average(),
            MinTimeMs = times.Min(),
            MaxTimeMs = times.Max(),
            Iterations = iterations
        };
    }

    private static Queue<int> PrepareCollection()
    {
        var queue = new Queue<int>(InitialSize);
        for (int i = 0; i < InitialSize; i++)
        {
            queue.Enqueue(i);
        }
        return queue;
    }

    public static List<PerformanceResult> MeasureAll()
    {
        var results = new List<PerformanceResult>();

        results.Add(MeasureOperation("AddToEnd", PrepareCollection, queue => queue.Enqueue(999999)));

        results.Add(MeasureOperation("RemoveFromStart", PrepareCollection, queue => queue.Dequeue()));

        results.Add(MeasureOperation("FindByValue", PrepareCollection, queue =>
        {
            for (int i = 0; i < 1000; i++)
            {
                queue.Contains(InitialSize / 2);
            }
        }));

        return results;
    }
}

