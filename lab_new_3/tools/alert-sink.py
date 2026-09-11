#!/usr/bin/env python3
"""Локальный приёмник уведомлений для проверки alerting'а.

Изображает webhook-канал (VK / MAX / Telegram / Slack): принимает POST
с JSON-телом и печатает полученный текст в stdout, откуда его видно
через `docker logs`. Нужен, чтобы на защите показать, что уведомление
действительно доставлено, и при этом ничего не отправлять наружу.

Запуск:
    docker run -d --name alert_sink \
        --network cproject_chakchakshop_network \
        -v "$PWD/tools/alert-sink.py:/app/alert-sink.py:ro" \
        -p 8099:8099 python:3.12-alpine python /app/alert-sink.py
"""
import json
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, HTTPServer

RECEIVED = []


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length).decode("utf-8")
        try:
            payload = json.loads(raw)
            text = payload.get("text", raw)
        except json.JSONDecodeError:
            text = raw

        stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S")
        RECEIVED.append({"at": stamp, "text": text})

        print(f"\n===== ALERT DELIVERED {stamp} =====", flush=True)
        print(text, flush=True)
        print("=" * 40, flush=True)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

    def do_GET(self):
        # GET /messages отдаёт всё принятое — удобно приложить к отчёту
        body = json.dumps(RECEIVED, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass  # служебные строки http.server только мешают читать лог


if __name__ == "__main__":
    print("alert-sink listening on :8099", flush=True)
    HTTPServer(("0.0.0.0", 8099), Handler).serve_forever()
