#!/usr/bin/env python3
"""Проверка, что роутер в C# и аналитика в SQL считают одно и то же.

Это не формальность. Раскладка пяти миллионов строк по шардам считалась
SQL-функцией shardlab.shard_hash(), а запросы в рантайме маршрутизирует
ShardHash.Compute() на C#. Разойдись эти две функции хоть на одном ключе —
сервис пойдёт за данными на узел, где их нет, и получит пустой ответ
вместо ошибки. Такую рассинхронизацию почти невозможно заметить в проде,
поэтому она проверяется явно.

Сверяются три величины: сам хеш, номер шарда по модулю и номер шарда
по кольцу.
"""
import json
import subprocess
import sys
import time
import urllib.request

API = "http://localhost:8090/api/sharding/route/"
KEY = "your-api-key-here-change-in-production"
SAMPLE = int(sys.argv[1]) if len(sys.argv) > 1 else 60
PACE = 0.7  # RateLimitingMiddleware: 100 запросов в минуту


def psql(sql):
    out = subprocess.run(
        ["docker", "exec", "chakchakshop_postgres", "psql", "-U", "postgres",
         "-d", "chakchakshop", "-tAF", "|", "-c", sql],
        capture_output=True, text=True, check=True).stdout
    return [line.split("|") for line in out.strip().splitlines() if line]


def main():
    rows = psql(f"""
        SELECT u.id::text,
               shardlab.shard_hash(u.id::text),
               shardlab.shard_by_modulo(u.id::text, 3),
               shardlab.shard_by_ring(u.id::text, 3)
        FROM users u ORDER BY md5(u.id::text) LIMIT {SAMPLE}
    """)

    print(f"### Сверка C# и SQL на {len(rows)} ключах\n")
    mismatches = []

    for i, (key, sql_hash, sql_mod, sql_ring) in enumerate(rows, 1):
        if i > 1:
            time.sleep(PACE)
        req = urllib.request.Request(API + key, headers={"X-API-Key": KEY})
        with urllib.request.urlopen(req, timeout=15) as resp:
            cs = json.load(resp)

        problems = []
        if str(cs["hash"]) != sql_hash:
            problems.append(f"hash: C#={cs['hash']} SQL={sql_hash}")
        if str(cs["byModulo"]) != sql_mod:
            problems.append(f"modulo: C#={cs['byModulo']} SQL={sql_mod}")
        if str(cs["byConsistentHashing"]) != sql_ring:
            problems.append(f"ring: C#={cs['byConsistentHashing']} SQL={sql_ring}")

        if problems:
            mismatches.append((key, problems))
            print(f"  РАСХОЖДЕНИЕ {key}: {'; '.join(problems)}")
        elif i <= 5:
            print(f"  {key}  hash={sql_hash}  modulo={sql_mod}  ring={sql_ring}  ✓")

    print()
    print(f"  проверено ключей:  {len(rows)}")
    print(f"  расхождений:       {len(mismatches)}")
    print("  вердикт:           " +
          ("ОК — реализации совпадают" if not mismatches else "ОШИБКА — реализации разошлись"))
    return 1 if mismatches else 0


if __name__ == "__main__":
    sys.exit(main())
