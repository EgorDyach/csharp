using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace ChakChakShop.API.Data.Sharding;

/// <summary>
/// Хеш ключа шардирования.
///
/// Требование к этой функции одно и оно жёсткое: её результат обязан
/// совпадать с SQL-функцией shardlab.shard_hash() до последнего бита.
/// Роутер по нему выбирает узел, а раскладка пяти миллионов строк
/// считалась в SQL — разойдись они, и запрос пошёл бы на шард, где
/// данных нет.
///
/// Поэтому НЕЛЬЗЯ использовать string.GetHashCode(): начиная с .NET Core
/// он рандомизирован и меняется от запуска к запуску процесса.
///
/// Берутся первые 15 шестнадцатеричных цифр MD5, то есть 60 бит.
/// Пятнадцать, а не шестнадцать — чтобы значение гарантированно
/// оставалось положительным в знаковом 64-битном целом и остаток от
/// деления не оказался отрицательным.
///
/// MD5 здесь не про криптографию, а про равномерность: ключ шардирования
/// не защищают, его распределяют.
/// </summary>
public static class ShardHash
{
    public static long Compute(string key)
    {
        var digest = MD5.HashData(Encoding.UTF8.GetBytes(key));
        var hex = Convert.ToHexString(digest).ToLowerInvariant();
        return long.Parse(hex.AsSpan(0, 15), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
    }

    public static long Compute(Guid key) => Compute(key.ToString());
}
