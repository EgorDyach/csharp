using System.Diagnostics;

namespace lab2.Performance;

public static class LinkedListPerformance
{
    private const int InitialSize = 100_000;

    private static PerformanceResult MeasureOperation(string operationName, Func<LinkedList<int>> prepareCollection, Action<LinkedList<int>> operation)
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
            CollectionType = "LinkedList",
            AverageTimeMs = (long)times.Average(),
            MinTimeMs = times.Min(),
            MaxTimeMs = times.Max(),
            Iterations = iterations
        };
    }

    private static LinkedList<int> PrepareCollection()
    {
        var list = new LinkedList<int>();
        for (int i = 0; i < InitialSize; i++)
        {
            list.AddLast(i);
        }
        return list;
    }

    public static List<PerformanceResult> MeasureAll()
    {
        var results = new List<PerformanceResult>();

        results.Add(MeasureOperation("AddToEnd", PrepareCollection, list => list.AddLast(999999)));

        results.Add(MeasureOperation("AddToStart", PrepareCollection, list => list.AddFirst(999999)));

        results.Add(MeasureOperation("AddToMiddle", PrepareCollection, list =>
        {
            int middleIndex = list.Count / 2;
            var node = list.First;
            for (int j = 0; j < middleIndex; j++)
            {
                node = node?.Next;
            }
            if (node != null)
            {
                list.AddAfter(node, 999999);
            }
        }));

        results.Add(MeasureOperation("RemoveFromStart", PrepareCollection, list => list.RemoveFirst()));

        results.Add(MeasureOperation("RemoveFromEnd", PrepareCollection, list => list.RemoveLast()));

        results.Add(MeasureOperation("RemoveFromMiddle", PrepareCollection, list =>
        {
            int middleIndex = list.Count / 2;
            var node = list.First;
            for (int j = 0; j < middleIndex; j++)
            {
                node = node?.Next;
            }
            if (node != null)
            {
                list.Remove(node);
            }
        }));

        results.Add(MeasureOperation("FindByValue", PrepareCollection, list =>
        {
            for (int i = 0; i < 1000; i++)
            {
                list.Contains(InitialSize / 2);
            }
        }));

        return results;
    }
}

