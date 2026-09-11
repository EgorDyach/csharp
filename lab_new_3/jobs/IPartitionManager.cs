namespace ChakChakShop.API.Services.Partitioning;

public interface IPartitionManager
{
    /// <summary>Существующие партиции конкретной таблицы.</summary>
    Task<IReadOnlyList<PartitionDescriptor>> GetPartitionsAsync(
        PartitionedTableOptions table, CancellationToken cancellationToken = default);

    /// <summary>
    /// Создаёт недостающие партиции на весь горизонт. Повторный запуск
    /// безопасен: уже существующие партиции не трогаются.
    /// </summary>
    Task<PartitionJobReport> EnsurePartitionsAsync(CancellationToken cancellationToken = default);

    /// <summary>Проверяет, существуют ли все партиции, которые должны существовать.</summary>
    Task<PartitionHealthReport> CheckHealthAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// Удаляет партицию. Нужна, чтобы воспроизвести аварию на защите:
    /// разрешено удалять только будущие партиции, данные удалить нельзя.
    /// </summary>
    Task DropFuturePartitionAsync(string table, string partition, CancellationToken cancellationToken = default);
}
