using System.Diagnostics;

namespace lab2.Performance;

public static class StackPerformance
{
    private const int InitialSize = 600_000;

    private static PerformanceResult MeasureOperation(string operationName, Func<Stack<int>> prepareCollection, Action<Stack<int>> operation)
    {
        const int iterations = 15;
        var times = new List<long>();

        for (int i = 0; i < iterations; i++)
        {
            var stack = prepareCollection();
            
            var stopwatch = Stopwatch.StartNew();
            operation(stack);
            stopwatch.Stop();
            times.Add(stopwatch.ElapsedMilliseconds);
        }

        return new PerformanceResult
        {
            OperationName = operationName,
            CollectionType = "Stack",
            AverageTimeMs = (long)times.Average(),
            MinTimeMs = times.Min(),
            MaxTimeMs = times.Max(),
            Iterations = iterations
        };
    }

    private static Stack<int> PrepareCollection()
    {
        var stack = new Stack<int>(InitialSize);
        for (int i = 0; i < InitialSize; i++)
        {
            stack.Push(i);
        }
        return stack;
    }

    public static List<PerformanceResult> MeasureAll()
    {
        var results = new List<PerformanceResult>();

        results.Add(MeasureOperation("AddToEnd", PrepareCollection, stack => stack.Push(999999)));

        results.Add(MeasureOperation("RemoveFromEnd", PrepareCollection, stack => stack.Pop()));

        results.Add(MeasureOperation("FindByValue", PrepareCollection, stack =>
        {
            for (int i = 0; i < 1000; i++)
            {
                stack.Contains(InitialSize / 2);
            }
        }));

        return results;
    }
}

