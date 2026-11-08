#!/usr/bin/env python3
"""A small save server for the game's cloud saves (Python 3.8+, standard library only).

Each device signs in with its own name and password (Basic auth). Saves live in
SAVES_ROOT/<game>/ (default ~/Saves/<game>); the one before an overwrite goes to
<game>/history/.

  GET  /v1/<game>/        {"<file>": {"size", "mtime", "sha256"}, ...}
  GET  /v1/<game>/<file>  the file, its time (unix seconds) in X-Mtime
  PUT  /v1/<game>/<file>  body + X-Mtime: 200, or 409 when the server's copy is newer

Run:
  saves_server.py --add-device ipad      prints the device's password (shown once)
  saves_server.py [port]                  serves http://127.0.0.1:<port> (default 8805)

Serve it over HTTPS from a reverse proxy (Caddy, nginx, a Cloudflare or Tailscale
tunnel): passwords travel in every request. Game ids: GAMES below.
"""
import base64, hashlib, hmac, json, os, re, secrets, shutil, sys, time, urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = os.path.expanduser(os.environ.get('SAVES_ROOT', '~/Saves'))
PASSWORDS = os.path.join(ROOT, '.devices')  # name:sha256(password) per line
GAMES = {'sims2pets'}
NAME = re.compile(r'^[A-Za-z0-9._ -]{1,128}$')
MAX_SIZE = 64 << 20


def devices():
    try:
        with open(PASSWORDS) as f:
            return dict(line.strip().split(':', 1) for line in f if ':' in line)
    except FileNotFoundError:
        return {}


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for block in iter(lambda: f.read(1 << 20), b''):
            h.update(block)
    return h.hexdigest()


class Handler(BaseHTTPRequestHandler):
    server_version = 'saves/1'

    def reply(self, status, body=b'', kind='application/json', headers=()):
        self.send_response(status)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        for k, v in headers:
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def device(self):
        """The signed-in device's name, or None (and a 401 sent)."""
        auth = self.headers.get('Authorization', '')
        if auth.startswith('Basic '):
            try:
                name, _, password = base64.b64decode(auth[6:]).decode().partition(':')
            except ValueError:
                name = password = ''
            digest = devices().get(name)
            if digest and hmac.compare_digest(digest, hashlib.sha256(password.encode()).hexdigest()):
                return name
        self.reply(401, headers=[('WWW-Authenticate', 'Basic realm="saves"')])
        return None

    def target(self):
        """(game folder, file name or ''), or None (and a 404 sent)."""
        m = re.match(r'^/v1/([a-z0-9-]+)/(.*)$', urllib.parse.unquote(self.path))
        if m and m.group(1) in GAMES and (m.group(2) == '' or NAME.match(m.group(2))):
            folder = os.path.join(ROOT, m.group(1))
            os.makedirs(folder, exist_ok=True)
            return folder, m.group(2)
        self.reply(404, b'{"error":"not found"}')
        return None

    def do_GET(self):
        if not self.device() or not (t := self.target()):
            return
        folder, name = t
        if not name:
            listing = {}
            for n in sorted(os.listdir(folder)):
                p = os.path.join(folder, n)
                if os.path.isfile(p) and NAME.match(n) and not n.endswith('.part'):
                    st = os.stat(p)
                    listing[n] = {'size': st.st_size, 'mtime': int(st.st_mtime), 'sha256': sha256_file(p)}
            return self.reply(200, json.dumps(listing).encode())
        path = os.path.join(folder, name)
        if not os.path.isfile(path):
            return self.reply(404, b'{"error":"no such save"}')
        with open(path, 'rb') as f:
            data = f.read()
        self.reply(200, data, 'application/octet-stream', [('X-Mtime', str(int(os.stat(path).st_mtime)))])

    def do_PUT(self):
        if not (device := self.device()) or not (t := self.target()):
            return
        folder, name = t
        size = int(self.headers.get('Content-Length', '-1'))
        if not name or size < 0 or size > MAX_SIZE:
            return self.reply(400, b'{"error":"a file name and a body up to 64 MB"}')
        try:
            mtime = int(self.headers.get('X-Mtime', ''))
        except ValueError:
            return self.reply(400, b'{"error":"X-Mtime header"}')
        data = self.rfile.read(size)
        path = os.path.join(folder, name)
        if os.path.isfile(path):
            if hashlib.sha256(data).hexdigest() == sha256_file(path):
                return self.reply(200, b'{"same":true}')
            if mtime < int(os.stat(path).st_mtime):
                return self.reply(409, b'{"error":"the server has a newer copy: pull it"}')
            os.makedirs(os.path.join(folder, 'history'), exist_ok=True)
            shutil.copy2(path, os.path.join(folder, 'history', f'{name}.{time.strftime("%Y%m%d-%H%M%S")}'))
        with open(path + '.part', 'wb') as f:
            f.write(data)
            f.flush()
            os.fsync(f.fileno())
        os.utime(path + '.part', (mtime, mtime))
        os.replace(path + '.part', path)
        print(f'{device} saved {os.path.basename(folder)}/{name} ({size} bytes)', flush=True)
        self.reply(200, b'{"saved":true}')

    def log_message(self, *args):
        pass  # one line per save (do_PUT), not per request


def add_device(name):
    if not NAME.match(name) or ':' in name:
        raise SystemExit('a device name of letters, digits, . _ - and spaces')
    password = secrets.token_urlsafe(18)
    entries = devices()
    entries[name] = hashlib.sha256(password.encode()).hexdigest()
    os.makedirs(ROOT, exist_ok=True)
    with open(PASSWORDS + '.part', 'w') as f:
        f.writelines(f'{n}:{d}\n' for n, d in entries.items())
    os.chmod(PASSWORDS + '.part', 0o600)
    os.replace(PASSWORDS + '.part', PASSWORDS)
    return password


if __name__ == '__main__':
    if sys.argv[1:2] == ['--add-device'] and len(sys.argv) > 2:
        print(f'password for {" ".join(sys.argv[2:])}: {add_device(" ".join(sys.argv[2:]))}')
    else:
        port = int(sys.argv[1]) if len(sys.argv) > 1 else 8805
        os.makedirs(ROOT, exist_ok=True)
        print(f'saves in {ROOT}, on http://127.0.0.1:{port}', flush=True)
        ThreadingHTTPServer(('127.0.0.1', port), Handler).serve_forever()
