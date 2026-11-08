#!/usr/bin/env python3
"""python3 server/test_saves_server.py: the save server's API, end to end, on a temporary folder."""
import base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 18805


def call(method, path, auth, body=None, headers=None):
    r = urllib.request.Request(f'http://127.0.0.1:{PORT}{path}', data=body, method=method, headers=headers or {})
    r.add_header('Authorization', 'Basic ' + base64.b64encode(auth.encode()).decode())
    try:
        with urllib.request.urlopen(r) as resp:
            return resp.status, resp.read(), resp.headers
    except urllib.error.HTTPError as e:
        return e.code, e.read(), e.headers


with tempfile.TemporaryDirectory() as root:
    env = dict(os.environ, SAVES_ROOT=root)
    server = [sys.executable, os.path.join(HERE, 'saves_server.py')]
    out = subprocess.run(server + ['--add-device', 'ipad'], env=env, capture_output=True, text=True, check=True).stdout
    login = 'ipad:' + out.rsplit(': ', 1)[1].strip()
    proc = subprocess.Popen(server + [str(PORT)], env=env, stdout=subprocess.DEVNULL)
    try:
        time.sleep(0.5)
        name = '/v1/sims2pets/69-G4OE-Sims%202%20Pets%20Save.gci'
        assert call('GET', '/v1/sims2pets/', 'ipad:wrong')[0] == 401
        assert call('GET', '/v1/other/', login)[0] == 404
        assert call('PUT', name, login, b'one', {'X-Mtime': '1000'})[0] == 200
        status, body, _ = call('GET', '/v1/sims2pets/', login)
        listing = json.loads(body)
        assert status == 200 and listing['69-G4OE-Sims 2 Pets Save.gci']['mtime'] == 1000, listing
        status, body, headers = call('GET', name, login)
        assert (status, body, headers['X-Mtime']) == (200, b'one', '1000')
        assert call('PUT', name, login, b'old', {'X-Mtime': '900'})[0] == 409
        assert call('PUT', name, login, b'two', {'X-Mtime': '2000'})[0] == 200
        assert len(os.listdir(os.path.join(root, 'sims2pets', 'history'))) == 1
        print('ok')
    finally:
        proc.terminate()
