#!/usr/bin/env python3
"""Temporary local relay for testing the vehicle API from an attached device.

Run this only on a trusted development machine. It forwards the app's already
formed API requests to the official BAPENDA host; it does not expose a public
endpoint or store request data.
"""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
import argparse


UPSTREAM = "https://sambara-v2.bapenda.jabarprov.go.id"
ALLOWED_PREFIX = "/api/renew-sambara/v2/"


class RelayHandler(BaseHTTPRequestHandler):
    server_version = "KendaraanRelay/1.0"

    def do_POST(self):  # noqa: N802 - required by BaseHTTPRequestHandler
        if not self.path.startswith(ALLOWED_PREFIX):
            self.send_error(404)
            return

        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        headers = {"Content-Type": self.headers.get("Content-Type", "application/json")}
        authorization = self.headers.get("Authorization")
        if authorization:
            headers["Authorization"] = authorization
        request = Request(
            UPSTREAM + self.path,
            data=body,
            headers=headers,
            method="POST",
        )
        try:
            with urlopen(request, timeout=30) as response:
                response_body = response.read()
                status = response.status
                content_type = response.headers.get("Content-Type", "application/json")
        except HTTPError as error:
            response_body = error.read()
            status = error.code
            content_type = error.headers.get("Content-Type", "application/json")
        except (TimeoutError, URLError) as error:
            self.send_error(504, explain=str(error))
            print(f"{self.path} -> upstream error: {error}", flush=True)
            return

        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(response_body)))
        self.end_headers()
        self.wfile.write(response_body)
        print(f"{self.path} -> {status} ({len(response_body)} bytes)", flush=True)

    def log_message(self, format, *args):
        print(f"relay {self.address_string()} - {format % args}", flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    server = ThreadingHTTPServer((args.host, args.port), RelayHandler)
    print(f"Relaying localhost:{args.port} -> {UPSTREAM}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
