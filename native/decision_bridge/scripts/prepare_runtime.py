"""Build DecisionRuntime or install a checksum-verified release archive."""
import argparse
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlparse
from urllib.request import urlopen

from _distribution import ROOT, extract_zip, sha256, verify_bundle


def install(archive, expected, root=ROOT):
    if len(expected) != 64 or any(c not in '0123456789abcdef' for c in expected.lower()):
        raise ValueError('Supply the 64-character SHA-256 from the release checksums.')
    if sha256(archive) != expected.lower():
        raise ValueError('Archive SHA-256 mismatch; the installed runtime was not changed.')
    apple = root / 'apple'
    apple.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.runtime-', dir=apple) as temporary:
        staged = Path(temporary)
        extract_zip(archive, staged)
        manifest = verify_bundle(staged, root)
        output = apple / 'DecisionRuntime.xcframework'
        backup = staged / 'previous.xcframework'
        if output.exists():
            output.rename(backup)
        try:
            (staged / 'DecisionRuntime.xcframework').rename(output)
        except BaseException:
            if backup.exists():
                backup.rename(output)
            raise
        (apple / 'runtime-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('DecisionRuntime installed and verified.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source', action='store_true', help='Build from the pinned source.')
    mode.add_argument('--archive', type=Path, help='Install a downloaded runtime ZIP.')
    mode.add_argument('--url', help='Download a runtime ZIP over HTTPS.')
    parser.add_argument('--sha256', help='Expected ZIP SHA-256 from the release checksums.')
    args = parser.parse_args()
    if args.source:
        subprocess.run([sys.executable, str(ROOT / 'scripts/build_apple.py')], check=True)
        return
    if not args.sha256:
        parser.error('--sha256 is required when installing a release archive')
    if args.archive:
        install(args.archive, args.sha256)
        return
    if urlparse(args.url).scheme != 'https':
        parser.error('--url must use HTTPS')
    with tempfile.TemporaryDirectory(prefix='d1-runtime-') as temporary:
        archive = Path(temporary) / 'runtime.zip'
        with urlopen(args.url, timeout=60) as response, archive.open('wb') as stream:
            if urlparse(response.url).scheme != 'https':
                raise ValueError('Runtime download redirected to a non-HTTPS URL.')
            total = 0
            for block in iter(lambda: response.read(1024 * 1024), b''):
                total += len(block)
                if total > 128 * 1024 * 1024:
                    raise ValueError('Runtime download exceeds the expected size.')
                stream.write(block)
        install(archive, args.sha256)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f'Runtime setup failed: {error}', file=sys.stderr)
        raise SystemExit(1)
