using System.Data;
using Npgsql;

namespace ChakChakShop.API.Data.Connections;

public class DbConnectionFactory : IDbConnectionFactory
{
    private readonly string _primaryConnectionString;
    private readonly string? _replicaConnectionString;
    private readonly ILogger<DbConnectionFactory> _logger;

    public DbConnectionFactory(IConfiguration configuration, ILogger<DbConnectionFactory> logger)
    {
        _primaryConnectionString = configuration.GetConnectionString("DefaultConnection")
            ?? throw new InvalidOperationException("Connection string 'DefaultConnection' not found.");

        var replica = configuration.GetConnectionString("ReplicaConnection");
        _replicaConnectionString = string.IsNullOrWhiteSpace(replica) ? null : replica;
        _logger = logger;

        if (_replicaConnectionString is null)
        {
            // Не ошибка: в dev-окружении реплики может не быть, и сервис
            // обязан работать, просто без масштабирования чтения.
            _logger.LogInformation("Replica connection is not configured — reads stay on primary");
        }
        else
        {
            _logger.LogInformation("Replica connection configured — list reads will be served by replica");
        }
    }

    public bool ReplicaConfigured => _replicaConnectionString is not null;

    public string ReadNodeName => ReplicaConfigured ? "replica" : "primary";

    public IDbConnection CreateWriteConnection() => new NpgsqlConnection(_primaryConnectionString);

    public IDbConnection CreateReadConnection() =>
        new NpgsqlConnection(_replicaConnectionString ?? _primaryConnectionString);
}
