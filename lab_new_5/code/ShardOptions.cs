namespace ChakChakShop.API.Data.Sharding;

public enum ShardStrategy
{
    Modulo,
    ConsistentHashing
}

public class ShardOptions
{
    public const string SectionName = "Sharding";

    public bool Enabled { get; set; }

    public ShardStrategy Strategy { get; set; } = ShardStrategy.Modulo;

    public int VirtualNodes { get; set; } = 256;

    /// <summary>
    /// Строки подключения к шардам по порядку: индекс в списке и есть
    /// номер шарда. Количество шардов берётся отсюда, а не из отдельной
    /// настройки — так их невозможно рассогласовать.
    /// </summary>
    public List<string> Connections { get; set; } = new();

    /// <summary>
    /// Таймаут одного шарда в распределённом запросе. Отдельный и короткий:
    /// в scatter-gather ответ приходит не быстрее самого медленного узла,
    /// и упавший шард не должен держать весь запрос до общего таймаута.
    /// </summary>
    public TimeSpan ShardTimeout { get; set; } = TimeSpan.FromSeconds(5);

    /// <summary>
    /// Отдавать ли частичный результат, если часть шардов недоступна.
    /// Для аналитики это разумно (с пометкой о неполноте), для денежных
    /// отчётов — нет.
    /// </summary>
    public bool AllowPartialResults { get; set; } = true;
}
