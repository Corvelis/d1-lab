"""Shared checks for portable DecisionRuntime release artifacts."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TARGETS = {'ios-arm64', 'ios-arm64-simulator', 'macos-arm64'}


def sha256(path):
    value = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def lock(root=ROOT):
    return json.loads((root / 'runtime.lock.json').read_text())


def source_fingerprint(root=ROOT):
    paths = [root / 'CMakeLists.txt', root / 'runtime.lock.json']
    paths += [root / 'scripts' / name for name in
              ['build_apple.py', 'patch_runtime.py', 'patch_media.py']]
    for directory in ['src', 'include']:
        paths += [p for p in (root / directory).rglob('*') if p.is_file()]
    value = hashlib.sha256()
    for path in sorted(paths):
        value.update(path.relative_to(root).as_posix().encode() + b'\0')
        value.update(path.read_bytes())
        value.update(b'\0')
    return value.hexdigest()


def check_portable(data, name):
    patterns = [
        rb'/(?:Users|home)/[^/\s\x00]+/',
        rb'/(?:private/)?var/folders/',
        rb'/(?:Volumes|opt/homebrew)/',
        rb'[A-Za-z]:\\Users\\',
        rb'docs/' + rb'internal',
        rb'\.' + rb'codex/',
        rb'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}',
        rb'gh[pousr]_[A-Za-z0-9]{30,}',
        rb'hf_[A-Za-z0-9]{25,}',
        rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',
    ]
    if any(re.search(pattern, data) for pattern in patterns):
        raise ValueError(f'Non-portable content in {name}; remove it before packaging.')


def extract_zip(archive, destination):
    """Extract ordinary files only, without traversal or archive links."""
    with zipfile.ZipFile(archive) as bundle:
        entries = bundle.infolist()
        if len(entries) > 256 or sum(e.file_size for e in entries) > 256 * 1024 * 1024:
            raise ValueError('Runtime archive exceeds the expected size.')
        seen = set()
        for entry in entries:
            path = PurePosixPath(entry.filename)
            mode = entry.external_attr >> 16
            if (path.is_absolute() or '..' in path.parts or '\\' in entry.filename
                    or ':' in entry.filename or stat.S_ISLNK(mode)
                    or entry.filename in seen):
                raise ValueError('Runtime archive contains an unsafe or duplicate path.')
            seen.add(entry.filename)
            target = destination.joinpath(*path.parts)
            if entry.is_dir():
                target.mkdir(parents=True, exist_ok=True)
            else:
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(bundle.read(entry))


def verify_bundle(directory, root=ROOT):
    manifest = json.loads((directory / 'runtime.json').read_text())
    pinned = lock(root)
    for key in ['runtimeVersion', 'llamaRevision', 'llamaArchiveSha256']:
        if manifest.get(key) != pinned[key]:
            raise ValueError(f'Runtime {key} does not match this source checkout.')
    if manifest.get('schemaVersion') != 1 or manifest.get('sourceSha256') != source_fingerprint(root):
        raise ValueError('Runtime was built from a different source version.')
    if set(manifest.get('targets', [])) != TARGETS:
        raise ValueError('Runtime must include iOS, arm64 simulator and macOS.')
    files = manifest.get('files', {})
    actual = {p.relative_to(directory).as_posix() for p in directory.rglob('*') if p.is_file()}
    if actual != set(files) | {'runtime.json'}:
        raise ValueError('Runtime file inventory does not match its manifest.')
    required = {'LICENSE', 'THIRD_PARTY_NOTICES.md'}
    required |= {'licenses/' + p.name for p in (root / 'licenses').iterdir() if p.is_file()}
    required |= {'DecisionRuntime.xcframework/Info.plist'}
    for target in TARGETS:
        required |= {f'DecisionRuntime.xcframework/{target}/libDecisionRuntime.a',
                     f'DecisionRuntime.xcframework/{target}/Headers/decision.h'}
    if not required <= set(files):
        raise ValueError('Runtime is missing a required library, header or license.')
    for name, expected in files.items():
        path = directory / name
        if sha256(path) != expected:
            raise ValueError(f'Runtime checksum mismatch: {name}')
        check_portable(path.read_bytes(), name)
    return manifest


def write_zip(directory, output):
    """Use relative names and stable timestamps; retain relative source symlinks."""
    with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as bundle:
        for path in sorted(directory.rglob('*')):
            if path.is_dir() and not path.is_symlink():
                continue
            name = path.relative_to(directory).as_posix()
            info = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            if path.is_symlink():
                info.external_attr = (stat.S_IFLNK | 0o777) << 16
                import os
                data = os.readlink(path).encode()
            else:
                info.external_attr = (stat.S_IFREG | 0o644) << 16
                data = path.read_bytes()
            check_portable(data, name)
            bundle.writestr(info, data)
