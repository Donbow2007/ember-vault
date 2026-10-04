#!/usr/bin/env python3
"""Release smoke test. No installs/downloads; optional existing GGUF for inference."""
import json, os, pathlib, socket, struct, subprocess, sys, tempfile, time, urllib.request
root = pathlib.Path(sys.argv[1]).resolve()
model = pathlib.Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None

def varint(n):
    out = bytearray()
    while n > 127:
        out.append((n & 127) | 128); n >>= 7
    return bytes(out + bytes([n]))
def field(n, value):
    return varint(n * 8 + 2) + varint(len(value)) + value

def fixture(path):
    feature = field(2, bytes([0, 0])) + bytes([24, 1]) + field(4, varint(9) + varint(4096) * 2)
    layer = field(1, b'places') + field(2, feature) + field(3, b'name') + field(4, field(1, b'Portable Smoke Place')) + bytes([40]) + varint(4096) + bytes([120, 2])
    tile = field(3, layer)
    directory = bytes([1, 0, 1]) + varint(len(tile)) + bytes([1])
    header = bytearray(127); header[:8] = b'PMTiles\x03'
    values = [127, len(directory), 127 + len(directory), 2, 0, 0, 129 + len(directory), len(tile), 1, 1, 1]
    for i, value in enumerate(values): struct.pack_into('<Q', header, 8 + i * 8, value)
    header[96:100] = bytes([1, 1, 1, 1])
    for offset, value in [(102, -10000000), (106, -10000000), (110, 10000000), (114, 10000000)]: struct.pack_into('<i', header, offset, value)
    path.write_bytes(header + directory + b'{}' + tile)

def fetch(url, data=None):
    return json.loads(urllib.request.urlopen(urllib.request.Request(url, data=json.dumps(data).encode() if data else None, headers={'Content-Type': 'application/json'}), timeout=90).read())

with tempfile.TemporaryDirectory(prefix='ember-smoke-') as temp:
    temp = pathlib.Path(temp); tools = temp / 'tools'; tools.mkdir(); storage = temp / 'storage'
    for name in ['bash', 'dirname', 'mkdir', 'cat']:
        (tools / name).symlink_to('/usr/bin/' + name)
    browser = temp / 'browser-url'
    (tools / 'xdg-open').write_text('#!/bin/bash\nprintf "%s" "$1" > "$EMBER_SMOKE_BROWSER"\n'); (tools / 'xdg-open').chmod(0o755)
    env = {**os.environ, 'PATH': str(tools), 'EMBER_VAULT_DATA_DIR': str(storage), 'EMBER_SMOKE_BROWSER': str(browser)}
    env.pop('PORT', None)
    occupied = socket.socket()
    try:
        occupied.bind(('127.0.0.1', 3000)); occupied.listen()
    except OSError as error:
        import errno
        if error.errno != errno.EADDRINUSE: raise
    launcher = root / 'portable/start-linux.sh'
    try:
        subprocess.run(['/bin/bash', str(launcher)], env=env, check=True)
        url = (storage / 'ember-vault.url').read_text().strip()
        assert url.endswith(':3100'), url
        for _ in range(20):
            if browser.exists(): break
            time.sleep(.1)
        assert browser.read_text() == url
        assert urllib.request.urlopen(url + '/up').status == 200
        gems = str(root / 'runtime/ruby/lib/ruby/gems/3.3.0')
        rails_env = {**env, 'PATH': str(root / 'runtime/ruby/bin') + ':' + str(tools), 'RAILS_ENV': 'production', 'GEM_HOME': gems, 'GEM_PATH': gems, 'BUNDLE_PATH': gems, 'BUNDLE_WITHOUT': 'development:test', 'BUNDLE_IGNORE_CONFIG': '1', 'EMBER_VAULT_BUNDLED_RUNTIME': '1', 'SECRET_KEY_BASE': (storage / '.secret_key_base').read_text(), 'LD_LIBRARY_PATH': str(root / 'runtime/llama/lib') + ':' + str(root / 'runtime/ruby/lib')}
        mapfile = storage / 'maps/smoke.pmtiles'; fixture(mapfile)
        code = 'abort unless RUBY_VERSION == "3.3.8"; abort unless MapIndexer.node_binary == Rails.root.join("runtime/node/bin/node").to_s; abort unless LocalAiServer.new(entry: ModelCatalog.entries.first).send(:executable) == Rails.root.join("runtime/llama/llama-server").to_s; puts "Rails #{Rails.version}; SQLite #{SQLite3::SQLITE_VERSION}"; pack = MapPack.create!(title: "Smoke", stored_path: "maps/smoke.pmtiles", format: "pmtiles", byte_size: File.size(EmberVault::PortableStorage.path("maps/smoke.pmtiles"))); MapIndexer.new(pack).call; abort unless pack.reload.map_features.first.name == "Portable Smoke Place"; puts "MapIndexer: bundled Node indexed fixture"'
        subprocess.run([str(root / 'runtime/ruby/bin/ruby'), str(root / 'bin/rails'), 'runner', code], env=rails_env, cwd=root, check=True)
        assert (storage / 'database/production.sqlite3').exists()
        assert (storage / '.secret_key_base').stat().st_mode & 0o777 == 0o600
        print('Fresh storage, database, Rails, bundled Node, occupied-port selection, browser URL and /up: PASS', flush=True)
        if model:
            for mode, layers in [('cpu-no-vulkan', '0'), ('vulkan', '999')]:
                ai_env = {**rails_env}
                if mode == 'cpu-no-vulkan': ai_env['VK_ICD_FILENAMES'] = '/nonexistent-vulkan-driver.json'
                logpath = temp / (mode + '.log')
                with logpath.open('w') as log:
                    process = subprocess.Popen([str(root / 'runtime/llama/llama-server'), '-m', str(model), '--host', '127.0.0.1', '--port', '18082', '-c', '512', '-t', '4', '-lv', '4', '--offline', '-ngl', layers], env=ai_env, stdout=log, stderr=log)
                    try:
                        for _ in range(240):
                            if process.poll() is not None: raise RuntimeError(logpath.read_text())
                            try:
                                if fetch('http://127.0.0.1:18082/health')['status'] == 'ok': break
                            except Exception: pass
                            time.sleep(.5)
                        else: raise RuntimeError('AI health timeout: ' + logpath.read_text())
                        result = fetch('http://127.0.0.1:18082/v1/completions', {'prompt': 'The capital of France is', 'max_tokens': 8, 'temperature': 0})
                        assert result['choices'][0]['text']
                        if mode == 'vulkan':
                            import re
                            assert re.search(r'offloaded [1-9][0-9]*/[0-9]+ layers to GPU', logpath.read_text()), logpath.read_text()
                        print(mode + ' health and inference: PASS', result['choices'][0]['text'], flush=True)
                    finally:
                        process.terminate()
                        try: process.wait(timeout=15)
                        except subprocess.TimeoutExpired: process.kill(); process.wait()
                print('\n'.join(line for line in logpath.read_text().splitlines() if 'Vulkan' in line or 'offloaded' in line), flush=True)
            (storage / 'models/survival-qwen-05b.gguf').symlink_to(model)
            ai_env = {**rails_env, 'EMBER_VAULT_AI_PORT': '18083', 'EMBER_VAULT_GPU_LAYERS': '0', 'VK_ICD_FILENAMES': '/nonexistent-vulkan-driver.json', 'EMBER_VAULT_AI_THREADS': '4', 'EMBER_VAULT_AI_TOKENS': '8'}
            code = 'ai = LocalAiRuntime.new(profile: "survival-qwen-05b"); begin; reply = ai.generate(Struct.new(:question).new("Say hello in one sentence.")); abort if reply.empty?; puts "Ember Vault LocalAiRuntime inference: #{reply}"; ensure; ai.send(:server).stop!; end'
            subprocess.run([str(root / 'runtime/ruby/bin/ruby'), str(root / 'bin/rails'), 'runner', code], env=ai_env, cwd=root, check=True)
    finally:
        subprocess.run(['/bin/bash', str(launcher), 'stop'], env=env, check=False)
        occupied.close()
