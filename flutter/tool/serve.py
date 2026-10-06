#!/usr/bin/env python3
"""Serve the Flutter web build and proxy the Reqall API on the same origin.

The Reqall server does not send CORS headers for its REST API yet
(fingerskier/reqall_net#124), so a browser build cannot call /api/v1
cross-origin. This serves build/web and forwards /api/*, /oauth/* and
/.well-known/* to the real server, which makes every API call same-origin.

    python3 tool/serve.py --bind 100.92.247.99 --port 8687
    python3 tool/serve.py --upstream https://www.reqall.net --dir build/web

Browser sign-in (OAuth) only works when the page is opened from localhost,
since the server accepts loopback redirect URIs only; elsewhere use an API key.
"""

import argparse
import http.client
import http.server
import os
import sys
import urllib.parse

PROXIED = ('/api/', '/oauth/', '/.well-known/')
HOP_BY_HOP = {
    'connection', 'keep-alive', 'proxy-authenticate', 'proxy-authorization', 'te', 'trailers',
    'transfer-encoding', 'upgrade', 'content-length', 'host', 'origin', 'referer', 'cookie',
}


def make_handler(directory, upstream):
    target = urllib.parse.urlsplit(upstream)

    class Handler(http.server.SimpleHTTPRequestHandler):
        def __init__(self, *args, **kwargs):
            super().__init__(*args, directory=directory, **kwargs)

        def _proxied(self):
            path = self.path.split('?', 1)[0]
            return any(path.startswith(p) for p in PROXIED)

        def _proxy(self):
            length = int(self.headers.get('Content-Length') or 0)
            body = self.rfile.read(length) if length else None
            headers = {k: v for k, v in self.headers.items() if k.lower() not in HOP_BY_HOP}
            conn_cls = http.client.HTTPSConnection if target.scheme == 'https' else http.client.HTTPConnection
            conn = conn_cls(target.netloc, timeout=60)
            try:
                conn.request(self.command, self.path, body=body, headers=headers)
                res = conn.getresponse()
                data = res.read()
            except OSError as e:
                self.send_error(502, f'Upstream unreachable: {e}')
                return
            finally:
                conn.close()
            self.send_response(res.status, res.reason)
            for k, v in res.getheaders():
                if k.lower() not in HOP_BY_HOP and k.lower() != 'set-cookie':
                    self.send_header(k, v)
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            if self.command != 'HEAD':
                self.wfile.write(data)

        def end_headers(self):
            if not self._proxied():
                # Always revalidate the app shell so a rebuild shows on reload.
                self.send_header('Cache-Control', 'no-cache')
            super().end_headers()

        def do_GET(self):
            self._proxy() if self._proxied() else super().do_GET()

        def do_HEAD(self):
            self._proxy() if self._proxied() else super().do_HEAD()

        def do_POST(self):
            self._proxy() if self._proxied() else self.send_error(405)

        def do_PATCH(self):
            self._proxy() if self._proxied() else self.send_error(405)

        def do_OPTIONS(self):
            self._proxy() if self._proxied() else self.send_error(405)

        def log_message(self, fmt, *args):
            if self._proxied():
                sys.stderr.write('%s %s\n' % (self.address_string(), fmt % args))

    return Handler


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    p = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    p.add_argument('--bind', default='127.0.0.1')
    p.add_argument('--port', type=int, default=8687)
    p.add_argument('--upstream', default=os.environ.get('REQALL_API_URL', 'https://www.reqall.net'))
    p.add_argument('--dir', default=os.path.join(here, '..', 'build', 'web'))
    a = p.parse_args()
    handler = make_handler(os.path.abspath(a.dir), a.upstream.rstrip('/'))
    server = http.server.ThreadingHTTPServer((a.bind, a.port), handler)
    print(f'Serving {os.path.abspath(a.dir)} on http://{a.bind}:{a.port}/ (API → {a.upstream})', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    main()
