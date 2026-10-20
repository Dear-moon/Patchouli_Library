import contextlib
import importlib.util
import io
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("export_source", Path(__file__).with_name("export_public_source.py"))
export_source = importlib.util.module_from_spec(spec)
spec.loader.exec_module(export_source)


class PublicSourceExportTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.base = Path(self.temporary.name).resolve()
        self.root = self.base / "project"
        for name in ("lib/main.dart", "android/local.properties", "android/key.properties", "android/project.iml",
                     "android/gradle/wrapper/gradle-wrapper.jar", "android/.gradle/cache.bin",
                     "android/app/src/main/jniLibs/arm64-v8a/libcpp.so",
                     "ios/Runner.xcodeproj/xcuserdata/private.xcuserstate",
                     "lib/performance_page.dart", "lib/render_budget_probe.dart",
                     "third_party/liquid_glass_easy/pubspec.yaml",
                     "third_party/liquid_glass_easy/LICENSE",
                     "third_party/liquid_glass_easy/lib/liquid_glass_easy.dart",
                     "flutter_screenshots/private.png", "LISTENING.md", "README.md", "docs/READER.md",
                     "docs/CLOUD_IMPORT.md", "docs/SEARCH.md",
                     "tools/update-mirror/index.mjs", "tools/update-mirror/worker.mjs",
                     "tools/update-mirror/build-site.mjs", "tools/update-mirror/wrangler.jsonc",
                     "tools/update-mirror/.wrangler/state/private.txt",
                     "tools/update-mirror/.dev.vars.production", "tools/update-mirror/.env.local",
                     "tools/update-mirror/node_modules/private.txt", "tools/update-mirror/public/index.html",
                     "tools/content-gateway/index.mjs", "tools/content-gateway/worker.mjs",
                     "tools/content-gateway/.dev.vars"):
            file = self.root / name
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text("fixture")

    def export(self, output, *args):
        with patch.object(export_source, "ROOT", self.root), \
                patch("sys.argv", ["export_public_source.py", str(output), *args]), \
                contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()):
            export_source.main()

    def test_public_candidate_excludes_private_runtime_without_changing_original(self):
        output = self.base / "complete"
        self.export(output)
        files = {p.relative_to(output).as_posix() for p in output.rglob("*") if p.is_file()}
        self.assertEqual(files, {"README.md", "docs/READER.md", "docs/CLOUD_IMPORT.md", "docs/SEARCH.md", "lib/main.dart",
            "third_party/liquid_glass_easy/pubspec.yaml",
            "third_party/liquid_glass_easy/LICENSE",
            "third_party/liquid_glass_easy/lib/liquid_glass_easy.dart",
            "android/gradle/wrapper/gradle-wrapper.jar",
            "tools/update-mirror/index.mjs", "tools/update-mirror/worker.mjs",
            "tools/update-mirror/build-site.mjs", "tools/update-mirror/wrangler.jsonc"})
        self.assertEqual((self.root / "android/app/src/main/jniLibs/arm64-v8a/libcpp.so").read_text(), "fixture")

    def test_source_only_is_explicit_and_leaves_runtime_out(self):
        output = self.base / "source-only"
        self.export(output, "--source-only")
        self.assertFalse(any(output.rglob("libcpp.so")))

    def test_restricted_component_aborts_before_creating_export(self):
        source = self.root / 'android/app/src/main/kotlin/WenkuWebCatalogClient.kt'
        source.parent.mkdir(parents=True)
        source.write_text('fixture')
        output = self.base / 'blocked'
        with self.assertRaises(SystemExit):
            self.export(output)
        self.assertFalse(output.exists())

    def test_secret_in_selected_source_cannot_be_exported(self):
        (self.root / 'lib/main.dart').write_text('ghp_' + 'a' * 40)
        output = self.base / 'secret'
        with self.assertRaises(SystemExit):
            self.export(output)
        self.assertFalse(output.exists())

    def test_never_overwrites_an_existing_export(self):
        output = self.base / "existing"
        output.mkdir()
        marker = output / "keep.txt"
        marker.write_text("keep")
        with self.assertRaises(SystemExit):
            self.export(output)
        self.assertEqual(marker.read_text(), "keep")

    def test_never_exports_recursively_into_the_source_tree(self):
        with self.assertRaises(SystemExit):
            self.export(self.root / "lib" / "output")


if __name__ == "__main__":
    unittest.main()
