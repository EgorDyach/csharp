using lab2.Performance;

namespace lab2;

class Program
{
    static void Main(string[] args)
    {
        var results = PerformanceMeasurer.MeasureAll();
        
        var report = ReportGenerator.GenerateTextReport(results);
        Console.WriteLine(report);
    }
}

