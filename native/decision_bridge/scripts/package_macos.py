"""Sign a release app with Developer ID and optionally notarize its ZIP."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess


def run(*arguments):
    subprocess.run(list(map(str, arguments)), check=True)


def archive(app, output):
    if output.exists():
        output.unlink()
    run('ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', app, output)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    parser.add_argument('--identity', required=True, help='Developer ID Application identity or its SHA-1.')
    parser.add_argument('--output', type=Path, required=True, help='A new output directory.')
    parser.add_argument('--notary-profile', help='Existing notarytool Keychain profile name.')
    args = parser.parse_args()
    if not args.app.is_dir() or args.app.suffix != '.app':
        parser.error('--app must point to a built .app bundle')
    if args.output.exists():
        parser.error('--output must be a new directory')
    args.output.mkdir(parents=True)
    app = args.output / args.app.name
    shutil.copytree(args.app, app, symlinks=True)
    # Sign nested code first. Never follow the links inside versioned frameworks.
    magic = {b'\xcf\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca'}
    for path in sorted(app.rglob('*'), key=lambda p: len(p.parts), reverse=True):
        if path.is_symlink():
            continue
        executable = False
        if path.is_file():
            with path.open('rb') as stream:
                executable = stream.read(4) in magic
        if executable or (path.is_dir() and path.suffix == '.framework'):
            run('codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime', path)
    entitlements = Path(__file__).resolve().parents[3] / 'apps/d1_lab/macos/Runner/Release.entitlements'
    run('codesign', '--force', '--sign', args.identity, '--timestamp', '--options', 'runtime',
        '--entitlements', entitlements, app)
    run('codesign', '--verify', '--deep', '--strict', app)
    info = subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(app / 'Contents/Info.plist')])
    version = json.loads(info)['CFBundleShortVersionString']
    output = args.output / f'D1-Lab-{version}-macos-arm64.zip'
    archive(app, output)
    notarized = False
    if args.notary_profile:
        # Submission is asynchronous; no credentials are written into files.
        result = subprocess.check_output([
            'xcrun', 'notarytool', 'submit', str(output), '--keychain-profile', args.notary_profile,
            '--output-format', 'json', '--no-progress'])
        submission = json.loads(result)
        (args.output / 'notary-submission.json').write_text(json.dumps(submission, indent=2) + '\n')
        print(f'Notary submission: {submission["id"]}')
        print('Run notarytool wait for this ID, then staple and validate the .app before distribution.')
    (args.output / 'release-status.json').write_text(json.dumps({
        'version': version, 'developerIdSigned': True, 'notarized': notarized,
        'readyForPublicDistribution': False,
    }, indent=2) + '\n')
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (args.output / 'SHA256SUMS').write_text(f'{digest}  {output.name}\n')
    print('Developer ID signature verified. Public distribution still requires notarization.')


if __name__ == '__main__':
    main()
