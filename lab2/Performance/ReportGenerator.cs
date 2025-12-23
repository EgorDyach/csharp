using lab2.Performance;

namespace lab2.Performance;

public class ReportGenerator
{
    public static string GenerateTextReport(List<PerformanceResult> results)
    {
        var report = new System.Text.StringBuilder();
        
        report.AppendLine("=".PadRight(80, '='));
        report.AppendLine("ОТЧЕТ О ПРОИЗВОДИТЕЛЬНОСТИ КОЛЛЕКЦИЙ");
        report.AppendLine("=".PadRight(80, '='));
        report.AppendLine();
        
        var groupedByCollection = results.GroupBy(r => r.CollectionType);
        
        foreach (var group in groupedByCollection)
        {
            report.AppendLine($"\n{group.Key}:");
            report.AppendLine("-".PadRight(80, '-'));
            report.AppendLine($"{"Операция",-25} {"Среднее (мс)",-15} {"Мин (мс)",-12} {"Макс (мс)",-12}");
            report.AppendLine("-".PadRight(80, '-'));
            
            foreach (var result in group.OrderBy(r => r.OperationName))
            {
                report.AppendLine($"{result.OperationName,-25} {result.AverageTimeMs,-15} {result.MinTimeMs,-12} {result.MaxTimeMs,-12}");
            }
        }
        
        report.AppendLine();
        report.AppendLine("=".PadRight(80, '='));
        report.AppendLine("АНАЛИЗ И ВЫВОДЫ");
        report.AppendLine("=".PadRight(80, '='));
        report.AppendLine();
        report.AppendLine(GenerateAnalysis(results));
        
        return report.ToString();
    }
    
    private static string GenerateAnalysis(List<PerformanceResult> results)
    {
        var analysis = new System.Text.StringBuilder();
        
        var operations = results.Select(r => r.OperationName).Distinct();
        
        foreach (var operation in operations)
        {
            var operationResults = results.Where(r => r.OperationName == operation).ToList();
            if (operationResults.Count < 2) continue;
            
            analysis.AppendLine($"\n{operation}:");
            var fastest = operationResults.OrderBy(r => r.AverageTimeMs).First();
            analysis.AppendLine($"  Самый быстрый: {fastest.CollectionType} ({fastest.AverageTimeMs} мс)");
            
            var slowest = operationResults.OrderByDescending(r => r.AverageTimeMs).First();
            if (slowest.CollectionType != fastest.CollectionType)
            {
                analysis.AppendLine($"  Самый медленный: {slowest.CollectionType} ({slowest.AverageTimeMs} мс)");
                var ratio = (double)slowest.AverageTimeMs / fastest.AverageTimeMs;
                analysis.AppendLine($"  Разница: {ratio:F2}x");
            }
        }
        
        analysis.AppendLine("\n\nОБЩИЕ ВЫВОДЫ:");
        analysis.AppendLine("1. List<T> эффективен для добавления в конец и доступа по индексу.");
        analysis.AppendLine("2. LinkedList<T> эффективен для добавления/удаления в начале и конце.");
        analysis.AppendLine("3. Queue<T> оптимизирован для операций FIFO (добавление в конец, удаление из начала).");
        analysis.AppendLine("4. Stack<T> оптимизирован для операций LIFO (добавление и удаление с конца).");
        analysis.AppendLine("5. ImmutableList<T> создает новую коллекцию при каждой операции, что влияет на производительность.");
        analysis.AppendLine("6. Поиск в LinkedList медленнее из-за необходимости последовательного прохода.");
        analysis.AppendLine("7. Добавление в начало List требует сдвига всех элементов.");
        
        return analysis.ToString();
    }
    
    public static void SaveReportToFile(string report, string filePath)
    {
        File.WriteAllText(filePath, report, System.Text.Encoding.UTF8);
    }
}

