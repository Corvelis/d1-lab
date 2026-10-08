"""Finalize a Mac package only after Apple has accepted its notary submission."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, required=True)
    parser.add_argument('--notary-profile', required=True)
    args = parser.parse_args()
    submission = json.loads((args.directory / 'notary-submission.json').read_text())
    result = json.loads(subprocess.check_output([
        'xcrun', 'notarytool', 'info', submission['id'], '--keychain-profile',
        args.notary_profile, '--output-format', 'json']))
    if result.get('status') != 'Accepted':
        parser.exit(2, f'Notarization is {result.get("status", "unknown")}; the package is not ready.\n')
    apps = list(args.directory.glob('*.app'))
    if len(apps) != 1:
        parser.error('Expected exactly one .app in the package directory')
    app = apps[0]
    for command in [
        ['xcrun', 'stapler', 'staple', str(app)],
        ['xcrun', 'stapler', 'validate', str(app)],
        ['codesign', '--verify', '--deep', '--strict', str(app)],
        ['spctl', '--assess', '--type', 'execute', str(app)],
    ]:
        subprocess.run(command, check=True)
    status_path = args.directory / 'release-status.json'
    status = json.loads(status_path.read_text())
    output = args.directory / f'D1-Lab-{status["version"]}-macos-arm64.zip'
    temporary = output.with_suffix('.zip.tmp')
    subprocess.run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent',
                    str(app), str(temporary)], check=True)
    temporary.replace(output)
    digest = hashlib.sha256(output.read_bytes()).hexdigest()
    (args.directory / 'SHA256SUMS').write_text(f'{digest}  {output.name}\n')
    status.update(notarized=True, readyForPublicDistribution=True)
    status_path.write_text(json.dumps(status, indent=2) + '\n')
    print('Notarization, stapled ticket, signature and Gatekeeper assessment verified.')


if __name__ == '__main__':
    main()
