"""Exercise release verification and rejection without model downloads."""
import json
from pathlib import Path
import re
import shutil
import stat
import sys
import tempfile
import unittest
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from _distribution import ROOT, TARGETS, check_portable, lock, sha256, source_fingerprint, write_zip
from prepare_runtime import install
from export_app import audit, copy_source


class DistributionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='d1-distribution-test-')
        self.directory = Path(self.temporary.name)
        self.root = self.directory / 'plugin'
        for name in ['src', 'include', 'scripts', 'licenses']:
            shutil.copytree(ROOT / name, self.root / name, ignore=shutil.ignore_patterns('__pycache__'))
        for name in ['runtime.lock.json', 'CMakeLists.txt', 'LICENSE', 'THIRD_PARTY_NOTICES.md']:
            shutil.copyfile(ROOT / name, self.root / name)
        self.output = self.root / 'apple/DecisionRuntime.xcframework'
        self.output.mkdir(parents=True)
        (self.output / 'existing.txt').write_text('existing runtime')
        self.bundle = self.directory / 'bundle'
        self.bundle.mkdir()
        shutil.copytree(self.root / 'licenses', self.bundle / 'licenses')
        for name in ['LICENSE', 'THIRD_PARTY_NOTICES.md']:
            shutil.copyfile(self.root / name, self.bundle / name)
        framework = self.bundle / 'DecisionRuntime.xcframework'
        framework.mkdir()
        (framework / 'Info.plist').write_text('test framework')
        for target in TARGETS:
            headers = framework / target / 'Headers'
            headers.mkdir(parents=True)
            (headers / 'decision.h').write_text('test header')
            (headers.parent / 'libDecisionRuntime.a').write_bytes(b'test archive')
        self.manifest = dict(lock(self.root), sourceSha256=source_fingerprint(self.root), targets=sorted(TARGETS))
        self.archive = self.directory / 'runtime.zip'
        self.pack()

    def tearDown(self):
        self.temporary.cleanup()

    def pack(self):
        self.manifest['files'] = {
            p.relative_to(self.bundle).as_posix(): sha256(p)
            for p in self.bundle.rglob('*') if p.is_file() and p.name != 'runtime.json'}
        (self.bundle / 'runtime.json').write_text(json.dumps(self.manifest))
        write_zip(self.bundle, self.archive)

    def assert_unchanged(self):
        self.assertEqual((self.output / 'existing.txt').read_text(), 'existing runtime')

    def test_verified_archive_replaces_runtime(self):
        install(self.archive, sha256(self.archive), self.root)
        self.assertFalse((self.output / 'existing.txt').exists())
        self.assertTrue((self.output / 'ios-arm64/libDecisionRuntime.a').exists())

    def test_wrong_archive_hash_preserves_runtime(self):
        with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
            install(self.archive, '0' * 64, self.root)
        self.assert_unchanged()

    def test_different_source_preserves_runtime(self):
        self.manifest['sourceSha256'] = '0' * 64
        self.pack()
        with self.assertRaisesRegex(ValueError, 'different source'):
            install(self.archive, sha256(self.archive), self.root)
        self.assert_unchanged()

    def test_modified_library_preserves_runtime(self):
        with zipfile.ZipFile(self.archive, 'r') as archive:
            contents = {entry.filename: archive.read(entry) for entry in archive.infolist()}
        contents['DecisionRuntime.xcframework/ios-arm64/libDecisionRuntime.a'] = b'changed'
        with zipfile.ZipFile(self.archive, 'w') as archive:
            for name, value in contents.items():
                archive.writestr(name, value)
        with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
            install(self.archive, sha256(self.archive), self.root)
        self.assert_unchanged()

    def test_missing_license_preserves_runtime(self):
        (self.bundle / 'licenses/json-MIT.txt').unlink()
        self.pack()
        with self.assertRaisesRegex(ValueError, 'required library, header or license'):
            install(self.archive, sha256(self.archive), self.root)
        self.assert_unchanged()

    def test_zip_traversal_and_symlink_preserve_runtime(self):
        for name, mode in [('../outside', stat.S_IFREG), ('link', stat.S_IFLNK)]:
            with zipfile.ZipFile(self.archive, 'w') as archive:
                entry = zipfile.ZipInfo(name)
                entry.external_attr = mode << 16
                archive.writestr(entry, b'outside')
            with self.assertRaisesRegex(ValueError, 'unsafe'):
                install(self.archive, sha256(self.archive), self.root)
            self.assert_unchanged()
        self.assertFalse((self.directory / 'outside').exists())

    def test_portability_check_rejects_home_paths(self):
        sample = ('/' + 'Users' + '/example/project/main.cpp').encode()
        with self.assertRaisesRegex(ValueError, 'Non-portable'):
            check_portable(sample, 'sample')
        check_portable(b'./src/decision.cpp', 'sample')

    def test_distribution_scripts_are_portable(self):
        for path in (ROOT / 'scripts').glob('*'):
            if path.is_file():
                check_portable(path.read_bytes(), path.name)


class SourceExportTests(unittest.TestCase):
    def test_export_uses_recipient_settings_and_excludes_run_data(self):
        with tempfile.TemporaryDirectory(prefix='d1-export-test-') as temporary:
            staged = Path(temporary) / 'source'
            staged.mkdir()
            copy_source(staged)
            audit(staged)
            app = staged / 'apps/d1_lab'
            for platform in ['ios', 'macos']:
                project = (app / platform / 'Runner.xcodeproj/project.pbxproj').read_text()
                self.assertNotRegex(project, r'DEVELOPMENT_TEAM\s*=\s*[A-Z0-9]{10}')
                identifiers = re.findall(r'PRODUCT_BUNDLE_IDENTIFIER\s*=\s*([^;]+);', project)
                self.assertTrue(identifiers)
                self.assertLessEqual(set(identifiers), {'app.d1lab.demo', 'app.d1lab.demo.RunnerTests'})
            settings = (app / 'macos/Runner/Configs/AppInfo.xcconfig').read_text()
            self.assertIn('PRODUCT_BUNDLE_IDENTIFIER = app.d1lab.demo', settings)
            self.assertIn('D1 Lab contributors.', settings)
            self.assertFalse((app / 'lib/smoke_main.dart').exists())
            self.assertFalse((app / 'lib/preview_main.dart').exists())
            self.assertTrue((staged / '.github/workflows/checks.yml').is_file())
            self.assertTrue((staged / 'LICENSE').is_file())
            for path in staged.rglob('*'):
                self.assertNotIn(path.suffix, {'.gguf', '.p12', '.p8', '.mobileprovision', '.provisionprofile'})


if __name__ == '__main__':
    unittest.main()
