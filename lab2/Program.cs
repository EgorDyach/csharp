using lab2.Performance;

namespace lab2;

class Program
{
    static void Main(string[] args)
    {
        var results = PerformanceMeasurer.MeasureAll();
        
        foreach (var result in results)
        {
            Console.WriteLine($"{result.CollectionType} {result.OperationName}: {result.AverageTimeMs} мс");
        }
    }
}

