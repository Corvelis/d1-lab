"""Create a standalone D1 Lab source archive from an explicit file selection."""
import argparse
import json
import os
from pathlib import Path
import posixpath
import re
import shutil
import tempfile

from _distribution import ROOT, check_portable, sha256, write_zip

APP = ROOT.parents[1] / 'apps/d1_lab'
IGNORED = {'build', 'Pods', '.symlinks', 'ephemeral', 'xcuserdata', '__pycache__', '.dart_tool'}
APP_FILES = {'.gitignore', '.metadata', 'README.md', 'LICENSE', 'CHANGELOG.md', 'THIRD_PARTY_NOTICES.md', 'analysis_options.yaml',
             'pubspec.yaml', 'pubspec.lock'}
NATIVE_FILES = {'.gitignore', 'README.md', 'README.en.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md',
                'pubspec.yaml', 'CMakeLists.txt', 'runtime.lock.json'}
LINKS = {
    'ios/DecisionRuntime.xcframework': '../apple/DecisionRuntime.xcframework',
    'macos/DecisionRuntime.xcframework': '../apple/DecisionRuntime.xcframework',
    'ios/Classes/DecisionBridgePlugin.swift': '../../apple/Classes/DecisionBridgePlugin.swift',
    'macos/Classes/DecisionBridgePlugin.swift': '../../apple/Classes/DecisionBridgePlugin.swift',
}


def app_settings(data, name):
    """Use portable demo identifiers and leave signing to the recipient."""
    if name.endswith('project.pbxproj'):
        data = re.sub(rb'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]+;', b'DEVELOPMENT_TEAM = "";', data)
        data = re.sub(
            rb'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);',
            lambda match: b'PRODUCT_BUNDLE_IDENTIFIER = app.d1lab.demo' +
            (b'.RunnerTests' if match[1].strip().strip(b'"').endswith(b'.RunnerTests') else b'') + b';', data)
    if name.endswith('AppInfo.xcconfig'):
        data = re.sub(rb'(?m)^PRODUCT_BUNDLE_IDENTIFIER\s*=.*$',
                      b'PRODUCT_BUNDLE_IDENTIFIER = app.d1lab.demo', data)
        data = re.sub(rb'(?m)^PRODUCT_COPYRIGHT\s*=.*$',
                      'PRODUCT_COPYRIGHT = Copyright © 2026 D1 Lab contributors.'.encode(), data)
    return data


def selected(root, directories, files):
    for path in sorted(root.rglob('*')):
        relative = path.relative_to(root)
        if any(part in IGNORED for part in relative.parts):
            continue
        if path.is_symlink() or path.is_dir():
            continue
        if relative.as_posix() in files or relative.parts[0] in directories:
            yield path, relative


def copy_source(staged):
    app = staged / 'apps/d1_lab'
    native = staged / 'native/decision_bridge'
    for source, relative in selected(APP, {'lib', 'test', 'docs', 'assets', 'ios', 'macos'}, APP_FILES):
        name = relative.as_posix()
        if name in {'lib/smoke_main.dart', 'lib/preview_main.dart'}:
            continue
        if relative.suffix in {'.lock'} and relative.name == 'Podfile.lock':
            continue
        if name.startswith('ios/Flutter/') and relative.name not in {
                'AppFrameworkInfo.plist', 'Debug.xcconfig', 'Release.xcconfig'}:
            continue
        if name.startswith('macos/Flutter/') and relative.name not in {
                'Flutter-Debug.xcconfig', 'Flutter-Release.xcconfig', 'GeneratedPluginRegistrant.swift'}:
            continue
        if relative.name.startswith('GeneratedPluginRegistrant') and not name.startswith('macos/'):
            continue
        if relative.suffix in {'.gguf', '.log', '.pyc'} or relative.name == '.DS_Store':
            continue
        if name == 'assets/branding/icon-prompt.txt':
            continue
        target = app / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        data = app_settings(data, name)
        check_portable(data, 'apps/d1_lab/' + name)
        target.write_bytes(data)
    for source, relative in selected(ROOT, {'src', 'include', 'lib', 'scripts', 'licenses', 'tests'}, NATIVE_FILES):
        target = native / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        data = source.read_bytes()
        check_portable(data, 'native/decision_bridge/' + relative.as_posix())
        target.write_bytes(data)
    for platform in ['ios', 'macos']:
        source = ROOT / platform / 'decision_bridge.podspec'
        target = native / platform / source.name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    (native / 'apple/Classes').mkdir(parents=True)
    shutil.copyfile(ROOT / 'apple/Classes/DecisionBridgePlugin.swift',
                    native / 'apple/Classes/DecisionBridgePlugin.swift')
    for name, value in LINKS.items():
        target = native / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(value)
    shutil.copyfile(ROOT / 'LICENSE', staged / 'LICENSE')
    shutil.copyfile(APP / 'CHANGELOG.md', staged / 'CHANGELOG.md')
    workflows = APP / '.github'
    if not workflows.exists():
        workflows = ROOT.parents[1] / '.github'
    shutil.copytree(workflows, staged / '.github')
    notices = (ROOT / 'THIRD_PARTY_NOTICES.md').read_text()
    notices = notices.replace('`licenses/`', '`native/decision_bridge/licenses/`')
    notices = notices.replace('`licenses/', '`native/decision_bridge/licenses/')
    notices = notices.replace('`runtime.lock.json`', '`native/decision_bridge/runtime.lock.json`')
    notices = notices.replace('`scripts/', '`native/decision_bridge/scripts/')
    app_notices = (APP / 'THIRD_PARTY_NOTICES.md').read_text()
    app_notices = app_notices.replace('# Third-party notices', '## App dependencies', 1)
    app_notices = app_notices.replace('(assets/licenses/', '(apps/d1_lab/assets/licenses/')
    app_notices = app_notices.replace('(../../native/', '(native/')
    notices += '\n' + app_notices
    (staged / 'THIRD_PARTY_NOTICES.md').write_text(notices)
    # Promote the app guide to the repository entry point with valid relative links.
    readme = (app / 'README.md').read_text()
    readme = re.sub(r'\]\((?!https?://|#)([^)]+)\)', r'](apps/d1_lab/\1)', readme)
    readme = readme.replace('(apps/d1_lab/docs/README.en.md)', '(README.en.md)')
    (staged / 'README.md').write_text(readme)
    readme_en = (app / 'docs/README.en.md').read_text()
    readme_en = re.sub(r'\]\((?!https?://|#)([^)]+)\)',
                       lambda match: '](' + posixpath.normpath('apps/d1_lab/docs/' + match[1]) + ')',
                       readme_en)
    readme_en = readme_en.replace('(apps/d1_lab/README.md)', '(README.md)')
    (staged / 'README.en.md').write_text(readme_en)
    (staged / '.gitignore').write_text(
        '**/.DS_Store\n**/__pycache__/\n**/*.pyc\n**/.dart_tool/\n**/build*/\n'
        '**/Pods/\n**/.symlinks/\n**/ephemeral/\n**/xcuserdata/\n'
        '**/third_party/\n**/apple/DecisionRuntime.xcframework/\n'
        '**/apple/runtime-build.json\n**/*.gguf\n**/*.part\n'
        '*.zip\nSHA256SUMS\ndist/\n')


def audit(staged):
    for path in staged.rglob('*'):
        relative = path.relative_to(staged).as_posix()
        if path.is_symlink():
            expected = LINKS.get(path.relative_to(staged / 'native/decision_bridge').as_posix())
            if os.readlink(path) != expected:
                raise ValueError(f'Unexpected symlink: {relative}')
            continue
        if path.is_file():
            if (path.suffix in {'.gguf', '.p12', '.p8', '.mobileprovision', '.provisionprofile', '.keychain'}
                    or path.name in {'.env', 'history.json', 'settings.json', 'tasks.json'}):
                raise ValueError(f'Private data or credentials cannot be exported: {relative}')
            check_portable(path.read_bytes(), relative)
            if path.suffix == '.md':
                for href in re.findall(r'\]\(([^)]+)\)', path.read_text()):
                    if '://' not in href and not href.startswith('#'):
                        target = path.parent / href.split('#', 1)[0]
                        if not target.exists():
                            raise ValueError(f'Broken documentation link in {relative}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', type=Path, required=True, help='New directory for the standalone source.')
    args = parser.parse_args()
    output = args.output.resolve()
    if output.exists():
        parser.error('--output must be a new directory')
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='.d1-source-', dir=output.parent) as temporary:
        staged = Path(temporary) / 'source'
        staged.mkdir()
        copy_source(staged)
        audit(staged)
        records = {p.relative_to(staged).as_posix(): sha256(p)
                   for p in sorted(staged.rglob('*')) if p.is_file() and not p.is_symlink()}
        links = {'native/decision_bridge/' + k: v for k, v in LINKS.items()}
        (staged / 'source-manifest.json').write_text(json.dumps(
            {'schemaVersion': 1, 'files': records, 'symlinks': links}, indent=2) + '\n')
        archive = output.parent / (output.name + '.zip')
        write_zip(staged, archive)
        shutil.move(staged, output)
    (output.parent / (output.name + '.sha256')).write_text(f'{sha256(archive)}  {archive.name}\n')
    print(f'Prepared {output.name}: {len(records)} files and {len(LINKS)} relative symlinks.')


if __name__ == '__main__':
    main()
