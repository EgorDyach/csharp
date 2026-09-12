using System.Data;

namespace ChakChakShop.API.Data.Connections;

/// <summary>
/// Маршрутизация подключений между Primary и Replica.
///
/// Правило простое и неизменное: всё, что меняет данные, идёт на Primary.
/// На Replica уходит только чтение, и только то, которое переживёт
/// отставание репликации на доли секунды.
/// </summary>
public interface IDbConnectionFactory
{
    /// <summary>Подключение к Primary: любые INSERT / UPDATE / DELETE и чтения, требующие свежих данных.</summary>
    IDbConnection CreateWriteConnection();

    /// <summary>
    /// Подключение к Replica для чтения. Если реплика не настроена,
    /// молча возвращает Primary — сервис должен работать и без неё.
    /// </summary>
    IDbConnection CreateReadConnection();

    /// <summary>Куда фактически уходят чтения: "replica" или "primary". Для заголовка X-Db-Node и диагностики.</summary>
    string ReadNodeName { get; }

    /// <summary>Настроена ли реплика в конфигурации.</summary>
    bool ReplicaConfigured { get; }
}
