#!/usr/bin/env python3
"""Project-local dependency builder. Never installs into system directories."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import shutil
import ssl
import subprocess
import sys
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]

def ensure_directories(root, names):
    root = root.resolve()
    for name in names:
        path = root / name
        if not path.resolve().is_relative_to(root):
            raise ValueError(f'Output escapes project: {path}')
        path.mkdir(parents=True, exist_ok=True)

def checked_output(root, path):
    root = root.resolve()
    if path.is_symlink() or not path.resolve().is_relative_to(root):
        raise ValueError(f'Unsafe output path: {path}')
    return path

def sha256(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def promote_verified(pending, target, digest):
    if sha256(pending) != digest:
        raise ValueError('Downloaded file checksum mismatch; existing file preserved')
    pending.replace(target)

def run(args, **kwargs):
    print('+', ' '.join(str(x) for x in args), flush=True)
    return subprocess.run([str(x) for x in args], check=True, cwd=ROOT, **kwargs)

def model(lock):
    item = lock['model']
    target = ROOT / 'models' / item['filename']
    if target.exists() and sha256(target) == item['sha256']:
        print('Verified existing model', flush=True)
        return
    # Python.org's macOS build may lack its own CA file; use the OS CA bundle,
    # keeping certificate and hostname validation enabled.
    context = ssl.create_default_context(cafile='/etc/ssl/cert.pem')
    pending = None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent, prefix='.download-', delete=False) as out:
            pending = Path(out.name)
            with urllib.request.urlopen(item['url'], context=context, timeout=60) as source:
                count = 0
                last = 0
                while chunk := source.read(1024 * 1024):
                    out.write(chunk)
                    count += len(chunk)
                    if count - last >= 128 * 1024 * 1024:
                        print(f'Model: {count // (1024*1024)} MiB downloaded', flush=True)
                        last = count
        if pending.stat().st_size != item['size']:
            raise ValueError('Model size mismatch')
        promote_verified(pending, target, item['sha256'])
        print('Model SHA-256 verified', flush=True)
    finally:
        if pending is not None and pending.exists():
            pending.unlink()

def engine(lock):
    env = ROOT / '.local' / 'build-env'
    if not (env / 'bin/python').exists():
        run([sys.executable, '-m', 'venv', env])
    cmake = env / 'bin/cmake'
    if not cmake.exists():
        run([env / 'bin/python', '-m', 'pip', 'install', '--only-binary=:all:', 'cmake==' + lock['cmake']])
    source = ROOT / 'vendor/whisper.cpp'
    if not source.exists():
        run(['git', 'clone', '--depth', '1', '--branch', lock['engine']['tag'], lock['engine']['repository'], source])
    actual = subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != lock['engine']['revision']:
        raise ValueError('Engine checkout does not match pinned revision')
    dirty = subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain', '--untracked-files=no'], text=True).strip()
    if dirty:
        raise ValueError('Pinned engine source has local modifications; preserve and review them before building')
    build = ROOT / '.local/engine-build'
    run([cmake, '-S', source, '-B', build, '-DCMAKE_BUILD_TYPE=Release',
         '-DGGML_METAL=ON', '-DGGML_METAL_EMBED_LIBRARY=ON', '-DBUILD_SHARED_LIBS=OFF',
         '-DWHISPER_BUILD_TESTS=OFF', '-DWHISPER_BUILD_SERVER=OFF'])
    run([cmake, '--build', build, '--target', 'whisper-cli', '-j', '4'])
    worker_build = ROOT / '.local/worker-build'
    run([cmake, '-S', ROOT / 'engine', '-B', worker_build, '-DCMAKE_BUILD_TYPE=Release',
         '-DGGML_METAL=ON', '-DGGML_METAL_EMBED_LIBRARY=ON', '-DBUILD_SHARED_LIBS=OFF',
         '-DWHISPER_BUILD_TESTS=OFF', '-DWHISPER_BUILD_SERVER=OFF'])
    run([cmake, '--build', worker_build, '--target', 'dictation-worker', '-j', '4'])

def app(lock):
    engine_path = ROOT / '.local/worker-build/bin/dictation-worker'
    model_path = ROOT / 'models' / lock['model']['filename']
    if not engine_path.is_file() or not model_path.is_file():
        raise ValueError('Run --engine first')
    if model_path.stat().st_size != lock['model']['size'] or sha256(model_path) != lock['model']['sha256']:
        raise ValueError('Model integrity check failed; run --engine to repair')
    run(['swift', 'build', '-c', 'release', '--product', 'LocalDictation'])
    # Sign outside the synced Documents tree: File Provider can attach Finder
    # metadata even to hidden project staging while codesign is sealing it.
    staging = Path(tempfile.mkdtemp(prefix='local-dictation-package-')).resolve()
    bundle = staging / 'VoiceTyping.app'
    ensure_directories(staging, ['VoiceTyping.app/Contents/MacOS', 'VoiceTyping.app/Contents/Resources'])
    executable = bundle / 'Contents/MacOS'
    resources = bundle / 'Contents/Resources'
    for path in [executable / 'LocalDictation', executable / 'dictation-worker', bundle / 'Contents/Info.plist',
                 resources / 'engine.json', resources / 'engine-lock.json', resources / 'WHISPER-LICENSE.txt']:
        checked_output(staging, path)
    shutil.copy(ROOT / '.build/release/LocalDictation', executable / 'LocalDictation')
    shutil.copy(engine_path, executable / 'dictation-worker')
    shutil.copy(ROOT / 'Resources/Info.plist', bundle / 'Contents/Info.plist')
    # Model is project-local rather than copied into every rebuild.
    config = dict(modelPath=str(model_path), modelSHA256=lock['model']['sha256'],
                  testDirectory=str(ROOT / 'fixtures/private'))
    (resources / 'engine.json').write_text(json.dumps(config, indent=2) + '\n')
    shutil.copy(ROOT / 'engine-lock.json', resources / 'engine-lock.json')
    shutil.copy(ROOT / 'vendor/whisper.cpp/LICENSE', resources / 'WHISPER-LICENSE.txt')
    # Finder may add display metadata after launch; only remove signing-incompatible
    # Finder metadata from this generated bundle, never quarantine/provenance.
    for path in [bundle, *bundle.rglob('*')]:
        checked_output(staging, path)
        attributes = subprocess.check_output(['/usr/bin/xattr', str(path)], text=True).splitlines()
        for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
            if attribute in attributes:
                run(['/usr/bin/xattr', '-d', attribute, path])
    run(['codesign', '--force', '--sign', '-', executable / 'dictation-worker'])
    run(['codesign', '--force', '--sign', '-', bundle])
    run(['codesign', '--verify', '--deep', '--strict', bundle])
    destination = checked_output(ROOT, ROOT / 'dist/VoiceTyping.app')
    if destination.exists():
        backup = ROOT / '.local' / ('previous-app-' + staging.name + '.app')
        destination.rename(backup)
    shutil.move(str(bundle), str(destination))
    staging.rmdir()
    run(['codesign', '--verify', '--deep', '--strict', destination])
    print('App ready:', destination)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--engine', action='store_true')
    parser.add_argument('--app', action='store_true')
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    ensure_directories(ROOT, ['.local', 'vendor', 'models', 'dist', '.planning', '.agents/context', 'docs/superpowers/specs', 'docs/superpowers/plans'])
    lock = json.loads((ROOT / 'engine-lock.json').read_text())
    if args.engine:
        with ThreadPoolExecutor(max_workers=2) as pool:
            futures = [pool.submit(model, lock), pool.submit(engine, lock)]
            for future in futures:
                future.result()
    if args.app:
        app(lock)
    if args.check:
        for path in ['.local/engine-build/bin/whisper-cli', 'models/' + lock['model']['filename'], 'dist/VoiceTyping.app']:
            print(path, 'present' if (ROOT / path).exists() else 'missing')

if __name__ == '__main__':
    main()
