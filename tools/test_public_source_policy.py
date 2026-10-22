import importlib.util
from pathlib import Path
import tempfile
import subprocess
import unittest

spec = importlib.util.spec_from_file_location('policy', Path(__file__).with_name('check_public_source.py'))
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


class PublicSourcePolicyTest(unittest.TestCase):
    def test_recognized_credentials_are_reported_without_printing_values(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            credential = 'ghp_' + 'a' * 40
            (root / 'source.dart').write_text(credential)
            issues = policy.inspect(root)
            self.assertEqual(len(issues), 1)
            self.assertNotIn(credential, issues[0])

    def test_private_paths_signing_files_and_device_identifiers_are_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'key.properties').write_text('fixture')
            (root / 'project.iml').write_text('fixture')
            (root / 'machine.txt').write_text('/' + 'Users/private/project')
            (root / 'device.txt').write_text('adb -s ' + 'ABCD1234567890')
            self.assertEqual(len(policy.inspect(root)), 4)

    def test_domain_models_and_preview_boundary_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'model.dart').write_text('class Book { final int id; Book(this.id); }')
            self.assertEqual(policy.inspect(root), [])

    def test_concrete_connectivity_files_are_blocked_without_dumping_content(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            file = root / 'WenkuWebCatalogClient.kt'
            file.write_text('private-fixture')
            issues = policy.inspect(root)
            self.assertEqual(len(issues), 1)
            self.assertIn('restricted connectivity component', issues[0])
            self.assertNotIn('private-fixture', issues[0])

    def test_renamed_native_binding_is_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'renamed.java').write_text('class Example { Object getMagicVersion' + 'Cpp(); }')
            self.assertTrue(any('restricted native binding' in issue for issue in policy.inspect(root)))

    def test_private_api_runtime_is_blocked_before_binary_decoding(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'android/app/src/main/jniLibs/arm64-v8a/libcpp.so'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'\x7fELF\xff\x00')
            issues = policy.inspect(root)
            self.assertEqual(len(issues), 1)
            self.assertIn('private API runtime', issues[0])

    def test_worker_secret_files_and_local_state_are_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for name in ['tools/update-mirror/.dev.vars.production',
                         'tools/content-gateway/.env.local',
                         'tools/update-mirror/.wrangler/state/local.txt']:
                file = root / name
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text('fixture')
            self.assertEqual(len(policy.inspect(root)), 3)

    def test_windows_sdk_version_is_not_an_ip_but_actual_lan_address_is(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'sdk.xml'
            source.write_text('WindowsTargetPlatformVersion=10.0.19041.0')
            self.assertEqual(policy.inspect(root), [])
            source.write_text('https://' + '192.168.' + '2.10/')
            self.assertEqual(len(policy.inspect(root)), 1)

    def test_only_exact_upstream_examples_are_allowed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'third_party/libmobi/src/read.c'
            source.parent.mkdir(parents=True)
            source.write_text(policy.UPSTREAM_PATH_EXAMPLES[source.relative_to(root).as_posix()])
            self.assertEqual(policy.inspect(root), [])
            source.write_text(source.read_text() + '\n/' + 'Users/private/local-book')
            self.assertEqual(len(policy.inspect(root)), 1)

    def test_inventory_requires_review_for_new_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'tools/public-source-files.txt').write_text('tools/public-source-files.txt\nmodel.dart\n')
            (root / 'model.dart').write_text('class Book {}')
            self.assertEqual(policy.inspect(root, require_manifest=True), [])
            (root / 'unexpected.txt').write_text('unreviewed')
            self.assertTrue(any('inventory review required' in issue for issue in policy.inspect(root)))

    def test_exact_license_doi_does_not_allow_private_addresses(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            source = root / 'assets/licenses/poi.txt'
            source.parent.mkdir(parents=True)
            source.write_text(policy.UPSTREAM_LICENSE_CITATIONS['assets/licenses/poi.txt'])
            self.assertEqual(policy.inspect(root), [])
            source.write_text(source.read_text() + '\nhttps://' + '192.168.' + '2.10/')
            self.assertEqual(len(policy.inspect(root)), 1)

    def test_renamed_provider_configuration_is_blocked(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'settings.txt').write_text('https://www.' + 'wenku8' + '.net/book/1.htm')
            self.assertTrue(any('restricted provider address' in issue for issue in policy.inspect(root)))

    def test_commit_is_checked_instead_of_a_cleaned_working_tree(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'tools').mkdir()
            (root / 'tools/public-source-files.txt').write_text('tools/public-source-files.txt\nconfig.txt\n')
            file = root / 'config.txt'
            file.write_text('https://www.' + 'wenku8' + '.net/book/1.htm')
            subprocess.run(['git', 'init', '-q', str(root)], check=True)
            subprocess.run(['git', '-C', str(root), 'add', 'tools/public-source-files.txt', 'config.txt'], check=True)
            subprocess.run(['git', '-C', str(root), '-c', 'user.name=Fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'fixture'], check=True)
            revision = subprocess.check_output(['git', '-C', str(root), 'rev-parse', 'HEAD'], text=True).strip()
            file.write_text('clean working tree')
            self.assertEqual(policy.inspect(root, require_manifest=True), [])
            self.assertTrue(any('restricted provider address' in issue for issue in policy.inspect_revision(root, revision)))


if __name__ == '__main__':
    unittest.main()
