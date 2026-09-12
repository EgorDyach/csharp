#!/usr/bin/env python3
"""Часть 6: как часто чтение с Replica сразу после записи видит старое значение.

POST /api/replication/lag-demo делает две вещи подряд без единой паузы:
записывает маркер на Primary и тут же читает то же поле на Replica.
Если прочитанное значение не совпало с записанным — поймано окно
replication lag. Здесь этот вызов повторяется N раз и считается доля промахов.
"""
import json
import statistics
import time
import sys
import urllib.error
import urllib.request

API = "http://localhost:8090/api/replication/lag-demo"
KEY = "your-api-key-here-change-in-production"
RUNS = int(sys.argv[1]) if len(sys.argv) > 1 else 100

# У сервиса стоит RateLimitingMiddleware: 100 запросов в минуту на ключ.
# Без паузы замер упирается в 429 и меряет не репликацию, а лимитер.
PACE_SECONDS = 0.7


def call():
    req = urllib.request.Request(API, method="POST", headers={"X-API-Key": KEY})
    with urllib.request.urlopen(req, timeout=15) as resp:
        return json.load(resp)


def main():
    fresh, stale, errors = 0, 0, 0
    stale_ms, fresh_ms = [], []

    print(f"### Замер: {RUNS} вызовов POST /api/replication/lag-demo")
    print("# запись на Primary и немедленное чтение того же ключа на Replica\n")

    for i in range(1, RUNS + 1):
        if i > 1:
            time.sleep(PACE_SECONDS)
        try:
            r = call()
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as exc:
            # Ошибку нельзя засчитывать как устаревшее чтение: это другой
            # класс события, и смешивать их в одной статистике нечестно.
            errors += 1
            print(f"  #{i:<4} ошибка запроса: {exc}")
            continue

        ms = float(r["elapsedMs"])
        if r["consistent"]:
            fresh += 1
            fresh_ms.append(ms)
        else:
            stale += 1
            stale_ms.append(ms)
            print(f"  #{i:<4} устаревшее чтение, между записью и чтением {ms:.3f} мс")

    counted = fresh + stale
    print()
    print(f"  успешных вызовов:   {counted}")
    print(f"  свежих чтений:      {fresh}")
    print(f"  устаревших чтений:  {stale}")
    print(f"  ошибок:             {errors}")
    if counted:
        print(f"  доля промахов:      {100.0 * stale / counted:.1f} %")
    if stale_ms:
        print(f"  промах: интервал запись→чтение  мин {min(stale_ms):.3f} / "
              f"медиана {statistics.median(stale_ms):.3f} / макс {max(stale_ms):.3f} мс")
    if fresh_ms:
        print(f"  успех:  интервал запись→чтение  мин {min(fresh_ms):.3f} / "
              f"медиана {statistics.median(fresh_ms):.3f} / макс {max(fresh_ms):.3f} мс")


if __name__ == "__main__":
    main()
