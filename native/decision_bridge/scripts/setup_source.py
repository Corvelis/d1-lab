"""Fetch, verify and patch the locked llama.cpp source."""
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys
import tarfile
import tempfile
from urllib.request import urlopen

from _distribution import ROOT, lock, sha256


def inventory(directory):
    return {p.relative_to(directory).as_posix(): sha256(p)
            for p in sorted(directory.rglob('*')) if p.is_file()}


def main():
    pinned = lock()
    patches = {name: sha256(ROOT / 'scripts' / name)
               for name in ['patch_runtime.py', 'patch_media.py']}
    source = ROOT / 'third_party/llama.cpp'
    stamp = ROOT / 'third_party/runtime-source.json'
    expected = dict(pinned, patches=patches)
    if source.is_dir() and stamp.is_file():
        recorded = json.loads(stamp.read_text())
        if all(recorded.get(key) == value for key, value in expected.items()):
            if recorded.get('files') == inventory(source):
                print('Pinned runtime source verified.')
                return
    source.parent.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.llama-', dir=source.parent) as temporary:
        staged = Path(temporary)
        archive = staged / 'source.tar.gz'
        url = f'https://codeload.github.com/ggml-org/llama.cpp/tar.gz/{pinned["llamaRevision"]}'
        print('Downloading the pinned llama.cpp source.', flush=True)
        with urlopen(url, timeout=60) as response, archive.open('wb') as output:
            shutil.copyfileobj(response, output)
        if sha256(archive) != pinned['llamaArchiveSha256']:
            raise ValueError('llama.cpp archive SHA-256 mismatch.')
        unpacked = staged / 'source'
        unpacked.mkdir()
        with tarfile.open(archive, 'r:gz') as bundle:
            for entry in bundle.getmembers():
                name = PurePosixPath(entry.name)
                if name.is_absolute() or '..' in name.parts or not (entry.isdir() or entry.isfile()):
                    raise ValueError('Source archive contains an unsafe entry.')
                path = unpacked.joinpath(*name.parts[1:])
                if entry.isdir():
                    path.mkdir(parents=True, exist_ok=True)
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    with bundle.extractfile(entry) as input_file, path.open('wb') as output:
                        shutil.copyfileobj(input_file, output)
        previous = staged / 'previous'
        if source.exists():
            source.rename(previous)
        unpacked.rename(source)
        try:
            for name in patches:
                subprocess.run([sys.executable, str(ROOT / 'scripts' / name)], check=True)
            expected['files'] = inventory(source)
            stamp.write_text(json.dumps(expected, indent=2) + '\n')
        except BaseException:
            shutil.rmtree(source)
            if previous.exists():
                previous.rename(source)
            raise
    print('Pinned runtime source prepared and verified.')


if __name__ == '__main__':
    main()
