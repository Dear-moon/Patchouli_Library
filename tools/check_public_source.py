#!/usr/bin/env python3
"""Reject restricted connectivity code, local artifacts and recognized secrets."""
from __future__ import annotations

import argparse
import io
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile
import tempfile

SKIP = {'.git', '.dart_tool', '.gradle', '.cxx', 'build', 'Pods', '__pycache__', '.symlinks'}
PRIVATE_NAMES = {'local.properties', 'key.properties', '.DS_Store', 'Generated.xcconfig',
                 'flutter_export_environment.sh', '.env', '.env.local'}
PRIVATE_DIRS = {'.local-notes', '.local-samples', '.wrangler', 'node_modules', 'flutter_screenshots', 'xcuserdata'}
PRIVATE_SUFFIXES = {'.iml', '.jks', '.keystore', '.pem', '.key', '.p12', '.mobileprovision', '.log', '.apk', '.aab'}
PRIVATE_COMPONENT_FILES = {
    'AccountSessionStore.kt', 'ApiSessionCookies.kt', 'IllustrationUrlPolicy.kt',
    'TokenManager.java', 'Wenku8Bridge.kt', 'WenkuEnginePlugins.kt',
    'WenkuPublicGateway.kt', 'WenkuPublicationSession.kt', 'WenkuWebCatalogClient.kt',
    'WenkuPublicWebClient.kt', 'WenkuWebSession.kt', 'WenkuOperationResult.kt',
    'WenkuSignIn.kt', 'WenkuSearch.kt', 'WenkuWebLibrary.kt',
    'wenku_web_catalogue.dart', 'wenku_web_reader.dart',
    'SessionFixtureInstrumentation.kt', 'CatalogReadInstrumentation.java',
    'provision_api_runtime.py', 'test_provision_api_runtime.py',
    'verify_apk_runtime.py', 'test_verify_apk_runtime.py',
    'WenkuApiForm.kt', 'WenkuOfficialWeb.kt', 'WenkuPublicSession.kt',
    'WenkuWebAuthentication.kt', 'WenkuWebReviews.kt', 'WenkuAccountPlugin.kt',
    'AccountRenewalInstrumentation.kt', 'DualRouteInstrumentation.java',
    'android-release.yml',
}
PRIVATE_COMPONENT_DIRS = {'tools/content-gateway', 'android/app/src/main/java/org/mewx/wenku8/api', 'studio-android'}
CONNECTIVITY_PATTERNS = {
    'restricted native binding': re.compile(r'getMagicVersion' + r'Cpp|System[.]loadLibrary\([\s\S]{0,40}[\"\']cpp[\"\']'),
    'restricted platform channel': re.compile(r'org[.]mewx[.]wenku8/' + r'legacy_api'),
    'restricted service endpoint': re.compile(r'https?://[\w.-]*wenku8[.](?:com|net|cc|cn)/(?:modules|api)/'),
    'restricted provider address': re.compile(r'\b(?:[a-z0-9-]+[.])*wenku8[.](?:com|net|cc|cn|org|ws)\b|\bpic[.]777743[.]xyz\b', re.I),
}
OCTET = r'(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])'
# Verified literal examples in unmodified libmobi v0.12, not local build paths.
UPSTREAM_PATH_EXAMPLES = {
    'third_party/libmobi/src/read.c': '/'.join(('', 'home', 'me', 'test.mobi')),
    'third_party/libmobi/tools/README.md': '/'.join(('', 'Users', 'baf', 'src', 'libmobi', 'tools', '.libs', 'mobitool')),
}
# This DOI in the unmodified Apache Commons Math notice is not a host address.
# Only the complete, reviewed citation in this license file is exempt.
UPSTREAM_LICENSE_CITATIONS = {
    'assets/licenses/poi.txt': 'http://citeseerx.ist.psu.edu/viewdoc/download;?doi=' + '10.1.1.' + '173.1898&rep=rep1&type=pdf',
}
PATTERNS = {
    'host home path': re.compile(r'[/](?:Users|home)[/][A-Za-z0-9_.-]+[/]'),
    'GitHub credential': re.compile(r'(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{40,})'),
    'private key': re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
    'AWS access key': re.compile(r'AKIA[A-Z0-9]{16}'),
    'personal device selector': re.compile(r'adb\s+-s\s+[A-Z0-9]{12,}'),
    'private LAN address': re.compile(rf'\b(?:192[.]168[.]{OCTET}[.]{OCTET}|10[.]{OCTET}[.]{OCTET}[.]{OCTET})\b'),
}


def inspect(root: Path, files=None, *, require_manifest=False) -> list[str]:
    issues = []
    manifest = root / 'tools/public-source-files.txt'
    allowed = set(manifest.read_text().splitlines()) if manifest.is_file() else None
    if require_manifest and allowed is None:
        issues.append('Source inventory is required')
    for file in sorted(root.rglob('*') if files is None else files):
        relative = file.relative_to(root)
        if any(part in SKIP for part in relative.parts):
            continue
        if file.is_symlink():
            issues.append(f'{relative}: symbolic link is not allowed in the public export')
            continue
        if not file.is_file():
            continue
        if allowed is not None and relative.as_posix() not in allowed:
            issues.append(f'{relative}: source inventory review required')
        if file.name in PRIVATE_COMPONENT_FILES or any(
            relative.as_posix() == name or relative.as_posix().startswith(name + '/')
            for name in PRIVATE_COMPONENT_DIRS
        ):
            issues.append(f'{relative}: restricted connectivity component')
            continue
        if file.name.lower() == 'libcpp.so':
            issues.append(f'{relative}: private API runtime must not be published in source')
            continue
        if file.name in PRIVATE_NAMES or file.name.startswith(('.env', '.dev.vars')) or file.suffix.lower() in PRIVATE_SUFFIXES or any(p in PRIVATE_DIRS for p in relative.parts):
            issues.append(f'{relative}: private or generated artifact')
            continue
        try:
            text = file.read_text(encoding='utf-8')
        except (UnicodeDecodeError, ValueError):
            continue
        for name, pattern in CONNECTIVITY_PATTERNS.items():
            if pattern.search(text):
                issues.append(f'{relative}: {name}')
        for name, pattern in PATTERNS.items():
            scanned = text
            if name == 'host home path' and relative.as_posix() in UPSTREAM_PATH_EXAMPLES:
                scanned = scanned.replace(UPSTREAM_PATH_EXAMPLES[relative.as_posix()], '<upstream example>')
            if name == 'private LAN address' and relative.as_posix() in UPSTREAM_LICENSE_CITATIONS:
                scanned = scanned.replace(UPSTREAM_LICENSE_CITATIONS[relative.as_posix()], '<upstream citation>')
            if pattern.search(scanned):
                # Never echo the matching credential or user data into CI logs.
                issues.append(f'{relative}: {name}')
    return issues


def inspect_revision(root: Path, revision: str) -> list[str]:
    if not re.fullmatch(r'[0-9a-f]{40,64}', revision):
        return ['Invalid commit identity']
    archive = subprocess.check_output(['git', '-C', str(root), 'archive', revision])
    tracked = set(subprocess.check_output(['git', '-C', str(root), 'ls-tree', '-r', '--name-only', '-z', revision]).decode().split('\0')) - {''}
    with tempfile.TemporaryDirectory(prefix='source-check-') as directory:
        with tarfile.open(fileobj=io.BytesIO(archive)) as content:
            archived = {item.name for item in content.getmembers() if item.isfile()}
            if tracked != archived:
                return ['Commit archive does not contain every tracked source file']
            for item in content.getmembers():
                name = PurePosixPath(item.name)
                if name.is_absolute() or '..' in name.parts or not (item.isdir() or item.isfile()):
                    return ['Commit contains an unsupported archive entry']
                target = Path(directory).joinpath(*name.parts)
                if item.isdir():
                    target.mkdir(parents=True, exist_ok=True)
                else:
                    target.parent.mkdir(parents=True, exist_ok=True)
                    target.write_bytes(content.extractfile(item).read())
        return inspect(Path(directory), require_manifest=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('root', type=Path, nargs='?', default=Path(__file__).resolve().parent.parent)
    parser.add_argument('--revision', help='Inspect the exact committed tree')
    args = parser.parse_args()
    issues = inspect_revision(args.root.resolve(), args.revision) if args.revision else inspect(args.root.resolve(), require_manifest=True)
    if issues:
        raise SystemExit('\n'.join(issues))
    print('Public source policy passed: no recognized restricted components or private artifacts.')


if __name__ == '__main__':
    main()
