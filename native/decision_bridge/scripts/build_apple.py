"""Build arm64 Apple runtime slices with embedded Metal kernel source."""
import argparse
import json
from pathlib import Path
import shutil
import shlex
import subprocess
import sys
import tempfile

from _distribution import ROOT, lock, source_fingerprint


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--slices', nargs='+', default=['macos', 'ios', 'simulator'],
                        choices=['macos', 'ios', 'simulator'])
    args = parser.parse_args()
    subprocess.run([sys.executable, str(ROOT / 'scripts/setup_source.py')], check=True)
    # Keep compiler diagnostics and embedded file names relative to the package.
    prefix_flags = ' '.join(shlex.quote(f'{flag}={ROOT}=.') for flag in
                            ['-ffile-prefix-map', '-fdebug-prefix-map'])
    targets = []
    for name in args.slices:
        build = ROOT / f'build-{name}'
        sdk = {'macos': 'macosx', 'ios': 'iphoneos', 'simulator': 'iphonesimulator'}[name]
        command = ['cmake', '-S', str(ROOT), '-B', str(build), '-DCMAKE_BUILD_TYPE=Release',
                   '-DCMAKE_OSX_ARCHITECTURES=arm64', f'-DCMAKE_OSX_SYSROOT={sdk}',
                   f'-DCMAKE_C_FLAGS={prefix_flags}', f'-DCMAKE_CXX_FLAGS={prefix_flags}',
                   '-DCMAKE_OSX_DEPLOYMENT_TARGET=' + ('14.0' if name == 'macos' else '16.0')]
        if name != 'macos':
            command += ['-DCMAKE_SYSTEM_NAME=iOS']
        subprocess.run(command, check=True)
        subprocess.run(['cmake', '--build', str(build), '-j', '8'], check=True)
        archives = [str(p) for p in sorted(build.rglob('*.a')) if p.name != 'libDecisionRuntime.a']
        subprocess.run(['xcrun', 'libtool', '-static', '-o', str(build / 'libDecisionRuntime.a'), *archives], check=True)
        targets.append({'macos': 'macos-arm64', 'ios': 'ios-arm64',
                        'simulator': 'ios-arm64-simulator'}[name])
    apple = ROOT / 'apple'
    apple.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.xcframework-', dir=apple) as temporary:
        staged = Path(temporary) / 'DecisionRuntime.xcframework'
        command = ['xcodebuild', '-create-xcframework']
        for name in args.slices:
            command += ['-library', str(ROOT / f'build-{name}/libDecisionRuntime.a'),
                        '-headers', str(ROOT / 'include')]
        subprocess.run(command + ['-output', str(staged)], check=True)
        output = apple / 'DecisionRuntime.xcframework'
        if output.exists():
            shutil.rmtree(output)
        staged.rename(output)
    manifest = dict(lock(), sourceSha256=source_fingerprint(), targets=targets)
    (apple / 'runtime-build.json').write_text(json.dumps(manifest, indent=2) + '\n')
    print('DecisionRuntime built successfully.')


if __name__ == '__main__':
    main()
