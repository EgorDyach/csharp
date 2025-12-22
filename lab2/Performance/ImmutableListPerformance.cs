using System.Diagnostics;
using System.Collections.Immutable;

namespace lab2.Performance;

public static class ImmutableListPerformance
{
    private const int InitialSize = 100_000;

    private static PerformanceResult MeasureOperation(string operationName, Func<ImmutableList<int>> prepareCollection, Func<ImmutableList<int>, ImmutableList<int>> operation)
    {
        const int iterations = 5;
        var times = new List<long>();

        for (int i = 0; i < iterations; i++)
        {
            var list = prepareCollection();
            
            var stopwatch = Stopwatch.StartNew();
            list = operation(list);
            stopwatch.Stop();
            times.Add(stopwatch.ElapsedMilliseconds);
        }

        return new PerformanceResult
        {
            OperationName = operationName,
            CollectionType = "ImmutableList",
            AverageTimeMs = (long)times.Average(),
            MinTimeMs = times.Min(),
            MaxTimeMs = times.Max(),
            Iterations = iterations
        };
    }

    private static PerformanceResult MeasureReadOperation(string operationName, Func<ImmutableList<int>> prepareCollection, Action<ImmutableList<int>> operation)
    {
        const int iterations = 5;
        var times = new List<long>();

        for (int i = 0; i < iterations; i++)
        {
            var list = prepareCollection();
            
            var stopwatch = Stopwatch.StartNew();
            operation(list);
            stopwatch.Stop();
            times.Add(stopwatch.ElapsedMilliseconds);
        }

        return new PerformanceResult
        {
            OperationName = operationName,
            CollectionType = "ImmutableList",
            AverageTimeMs = (long)times.Average(),
            MinTimeMs = times.Min(),
            MaxTimeMs = times.Max(),
            Iterations = iterations
        };
    }

    private static ImmutableList<int> PrepareCollection()
    {
        var list = ImmutableList<int>.Empty;
        for (int i = 0; i < InitialSize; i++)
        {
            list = list.Add(i);
        }
        return list;
    }

    public static List<PerformanceResult> MeasureAll()
    {
        var results = new List<PerformanceResult>();

        results.Add(MeasureOperation("AddToEnd", PrepareCollection, list => list.Add(999999)));

        results.Add(MeasureOperation("AddToStart", PrepareCollection, list => list.Insert(0, 999999)));

        results.Add(MeasureOperation("AddToMiddle", PrepareCollection, list =>
        {
            int middleIndex = list.Count / 2;
            return list.Insert(middleIndex, 999999);
        }));

        results.Add(MeasureOperation("RemoveFromStart", PrepareCollection, list => list.RemoveAt(0)));

        results.Add(MeasureOperation("RemoveFromEnd", PrepareCollection, list => list.RemoveAt(list.Count - 1)));

        results.Add(MeasureOperation("RemoveFromMiddle", PrepareCollection, list =>
        {
            int middleIndex = list.Count / 2;
            return list.RemoveAt(middleIndex);
        }));

        results.Add(MeasureReadOperation("FindByValue", PrepareCollection, list =>
        {
            for (int i = 0; i < 1000; i++)
            {
                list.Contains(InitialSize / 2);
            }
        }));

        results.Add(MeasureReadOperation("GetByIndex", PrepareCollection, list =>
        {
            for (int i = 0; i < 1000; i++)
            {
                var _ = list[InitialSize / 2];
            }
        }));

        return results;
    }
}

