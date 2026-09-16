using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using ChakChakShop.API.Data.Sharding;

namespace ChakChakShop.API.Controllers;

/// <summary>
/// Наблюдение за шардированным кластером: куда роутер отправляет ключ,
/// как выглядят single-shard и распределённые запросы, что происходит
/// при отказе узла.
/// </summary>
[ApiController]
[Route("api/[controller]")]
[Authorize(AuthenticationSchemes = $"ApiKey,{JwtBearerDefaults.AuthenticationScheme}", Roles = "ApiKey,Admin")]
public class ShardingController : ControllerBase
{
    private readonly ShardedOrderReader _reader;

    public ShardingController(ShardedOrderReader reader) => _reader = reader;

    /// <summary>Куда роутер отправит конкретный ключ.</summary>
    [HttpGet("route/{shardKey}")]
    public IActionResult Route(string shardKey)
    {
        var modulo = new ModuloShardRouter(_reader.ShardCount);
        var ring = new ConsistentHashRouter(_reader.ShardCount);

        return Ok(new
        {
            shardKey,
            hash = ShardHash.Compute(shardKey),
            activeRouter = _reader.Router.Name,
            activeShard = _reader.Router.ResolveShard(shardKey),
            byModulo = modulo.ResolveShard(shardKey),
            byConsistentHashing = ring.ResolveShard(shardKey)
        });
    }

    /// <summary>Доля кольца на каждый шард — видно, насколько ровно легли vnode.</summary>
    [HttpGet("ring")]
    public IActionResult Ring([FromQuery] int shards = 3, [FromQuery] int vnodes = 256)
    {
        var ring = new ConsistentHashRouter(shards, vnodes);
        return Ok(new { shards, vnodes, sharePercent = ring.RingShare() });
    }

    /// <summary>Single-shard query: работает ровно один узел.</summary>
    [HttpGet("orders/{userId:guid}")]
    public async Task<IActionResult> UserOrders(Guid userId, [FromQuery] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        var result = await _reader.GetUserOrdersAsync(userId, limit, cancellationToken);
        return Ok(new
        {
            shardsQueried = result.ShardsQueried,
            elapsedMs = result.ElapsedMs,
            rows = result.Rows.Count,
            data = result.Rows
        });
    }

    /// <summary>Локальный JOIN внутри одного шарда.</summary>
    [HttpGet("orders/{userId:guid}/items")]
    public async Task<IActionResult> UserOrdersWithItems(Guid userId, [FromQuery] int limit = 20,
        CancellationToken cancellationToken = default)
    {
        var result = await _reader.GetUserOrdersWithItemsAsync(userId, limit, cancellationToken);
        return Ok(new { shardsQueried = result.ShardsQueried, elapsedMs = result.ElapsedMs, data = result.Rows });
    }

    /// <summary>Распределённая агрегация: опрашиваются все узлы, сумма считается здесь.</summary>
    [HttpGet("count")]
    public async Task<IActionResult> Count(CancellationToken cancellationToken)
    {
        var result = await _reader.CountAllAsync(cancellationToken);
        return Ok(new
        {
            total = result.Rows.Sum(r => r.Count),
            perShard = result.Rows.OrderBy(r => r.Shard),
            shardsQueried = result.ShardsQueried,
            failedShards = result.FailedShards,
            complete = result.Complete,
            elapsedMs = result.ElapsedMs
        });
    }

    /// <summary>ORDER BY ... LIMIT поверх нескольких узлов: top-N с каждого, слияние в приложении.</summary>
    [HttpGet("newest")]
    public async Task<IActionResult> Newest([FromQuery] int limit = 20, CancellationToken cancellationToken = default)
    {
        var result = await _reader.GetNewestAsync(limit, cancellationToken);
        return Ok(new
        {
            shardsQueried = result.ShardsQueried,
            failedShards = result.FailedShards,
            complete = result.Complete,
            elapsedMs = result.ElapsedMs,
            data = result.Rows
        });
    }
}
