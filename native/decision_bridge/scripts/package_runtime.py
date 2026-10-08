"""Package a matching XCFramework with checksums and third-party licenses."""
import argparse
import json
from pathlib import Path
import shutil
import tempfile

from _distribution import ROOT, lock, sha256, source_fingerprint, verify_bundle, write_zip


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='Directory for release files.')
    args = parser.parse_args()
    pinned = lock()
    build = json.loads((ROOT / 'apple/runtime-build.json').read_text())
    if build.get('sourceSha256') != source_fingerprint():
        raise ValueError('Source has changed; rebuild DecisionRuntime before packaging.')
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='d1-package-') as temporary:
        staged = Path(temporary)
        shutil.copytree(ROOT / 'apple/DecisionRuntime.xcframework', staged / 'DecisionRuntime.xcframework')
        shutil.copytree(ROOT / 'licenses', staged / 'licenses')
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
            shutil.copyfile(ROOT / name, staged / name)
        manifest = dict(pinned, sourceSha256=build['sourceSha256'], targets=build['targets'])
        manifest['files'] = {p.relative_to(staged).as_posix(): sha256(p)
                             for p in sorted(staged.rglob('*')) if p.is_file()}
        (staged / 'runtime.json').write_text(json.dumps(manifest, indent=2) + '\n')
        verify_bundle(staged)
        filename = f'DecisionRuntime-{pinned["runtimeVersion"]}-apple-arm64.zip'
        output = args.output / filename
        write_zip(staged, output)
        shutil.copyfile(staged / 'runtime.json', args.output / 'runtime.json')
    (args.output / 'SHA256SUMS').write_text(f'{sha256(output)}  {output.name}\n')
    print(f'Prepared {output.name} and SHA256SUMS.')


if __name__ == '__main__':
    main()
