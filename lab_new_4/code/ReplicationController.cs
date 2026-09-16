using Dapper;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ChakChakShop.API.Data.Connections;

namespace ChakChakShop.API.Controllers;

/// <summary>
/// Наблюдение за репликацией: куда уходят запросы, насколько отстаёт
/// Replica и что видно сразу после записи.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(AuthenticationSchemes = $"ApiKey,{JwtBearerDefaults.AuthenticationScheme}", Roles = "ApiKey,Admin")]
public class ReplicationController : ControllerBase
{
    private readonly IDbConnectionFactory _connections;

    public ReplicationController(IDbConnectionFactory connections) => _connections = connections;

    /// <summary>
    /// Доказательство маршрутизации: одно и то же обращение на обе строки
    /// подключения. pg_is_in_recovery() возвращает true только на standby.
    /// </summary>
    [HttpGet("where-am-i")]
    public async Task<IActionResult> WhereAmI(CancellationToken cancellationToken)
    {
        const string sql = @"
            SELECT pg_is_in_recovery()            AS inRecovery,
                   inet_server_addr()::text       AS address,
                   current_setting('server_version') AS version";

        using var write = _connections.CreateWriteConnection();
        using var read = _connections.CreateReadConnection();

        var onWrite = await write.QuerySingleAsync(
            new CommandDefinition(sql, cancellationToken: cancellationToken));
        var onRead = await read.QuerySingleAsync(
            new CommandDefinition(sql, cancellationToken: cancellationToken));

        return Ok(new
        {
            replicaConfigured = _connections.ReplicaConfigured,
            readsGoTo = _connections.ReadNodeName,
            writeConnection = new { inRecovery = (bool)onWrite.inrecovery, address = (string?)onWrite.address, role = (bool)onWrite.inrecovery ? "replica" : "primary" },
            readConnection = new { inRecovery = (bool)onRead.inrecovery, address = (string?)onRead.address, role = (bool)onRead.inrecovery ? "replica" : "primary" }
        });
    }

    /// <summary>Состояние репликации с обеих сторон: байты и секунды отставания.</summary>
    [HttpGet("status")]
    public async Task<IActionResult> Status(CancellationToken cancellationToken)
    {
        const string primarySql = @"
            SELECT application_name                                              AS applicationName,
                   client_addr::text                                             AS clientAddr,
                   state,
                   sync_state                                                    AS syncState,
                   sent_lsn::text                                                AS sentLsn,
                   replay_lsn::text                                              AS replayLsn,
                   pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)             AS behindBytes,
                   extract(epoch from replay_lag)                                AS replayLagSeconds
            FROM pg_stat_replication";

        const string replicaSql = @"
            SELECT pg_is_in_recovery()                                           AS inRecovery,
                   pg_last_wal_receive_lsn()::text                               AS receivedLsn,
                   pg_last_wal_replay_lsn()::text                                AS replayedLsn,
                   pg_last_xact_replay_timestamp()                               AS lastAppliedTx,
                   extract(epoch from (now() - pg_last_xact_replay_timestamp())) AS behindSeconds";

        using var write = _connections.CreateWriteConnection();
        var standbys = await write.QueryAsync(
            new CommandDefinition(primarySql, cancellationToken: cancellationToken));

        object? replica = null;
        if (_connections.ReplicaConfigured)
        {
            using var read = _connections.CreateReadConnection();
            replica = await read.QuerySingleAsync(
                new CommandDefinition(replicaSql, cancellationToken: cancellationToken));
        }

        return Ok(new { primary = new { standbys }, replica });
    }

    /// <summary>
    /// Демонстрация replication lag: запись на Primary и немедленное чтение
    /// того же значения на Replica, без единой паузы между ними.
    /// </summary>
    [HttpPost("lag-demo")]
    public async Task<IActionResult> LagDemo(CancellationToken cancellationToken)
    {
        var marker = $"lag-demo-{Guid.NewGuid():N}";

        using var write = _connections.CreateWriteConnection();
        var writtenAt = await write.ExecuteScalarAsync<DateTime>(new CommandDefinition(@"
            INSERT INTO categories (id, name, description, created_at)
            VALUES ('dddddddd-dddd-dddd-dddd-ddddddddddd3', @Marker, 'replication lag demo', NOW())
            ON CONFLICT (id) DO UPDATE SET name = EXCLUDED.name, updated_at = NOW()
            RETURNING NOW()", new { Marker = marker }, cancellationToken: cancellationToken));

        // Никаких Task.Delay: читаем ровно в тот момент, когда Primary уже
        // подтвердил COMMIT. Если значение не совпало — поймано окно lag'а.
        using var read = _connections.CreateReadConnection();
        var seenOnReplica = await read.ExecuteScalarAsync<string?>(new CommandDefinition(
            "SELECT name FROM categories WHERE id = 'dddddddd-dddd-dddd-dddd-ddddddddddd3'",
            cancellationToken: cancellationToken));

        var readAt = DateTime.UtcNow;
        var consistent = string.Equals(marker, seenOnReplica, StringComparison.Ordinal);

        return Ok(new
        {
            writtenOnPrimary = marker,
            seenOnReplica,
            consistent,
            verdict = consistent
                ? "Replica успела применить изменение до чтения"
                : "Поймано окно replication lag: Replica ещё отдаёт старое значение",
            elapsedMs = (readAt - writtenAt.ToUniversalTime()).TotalMilliseconds
        });
    }
}
