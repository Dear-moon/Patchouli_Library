#!/usr/bin/env python3
"""Export the reviewed public inventory without local development material."""
import argparse
import importlib.util
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parent.parent
spec = importlib.util.spec_from_file_location('public_policy', ROOT / 'tools/check_public_source.py')
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('output', type=Path)
    parser.add_argument('--source-only', action='store_true', help='Compatibility alias; every export is source-only')
    args = parser.parse_args()
    destination = args.output.resolve()
    if destination == ROOT or ROOT.is_relative_to(destination) or destination.is_relative_to(ROOT):
        parser.error('Choose an empty destination outside the source tree')
    if destination.exists() and any(destination.iterdir()):
        parser.error('Destination must be empty; existing files are never removed')
    names = (ROOT / 'tools/public-source-files.txt').read_text().splitlines()
    if len(names) != len(set(names)) or any(Path(n).is_absolute() or '..' in Path(n).parts for n in names):
        parser.error('Invalid source inventory')
    files = [ROOT / name for name in names]
    if any(not file.is_file() or file.is_symlink() for file in files):
        parser.error('Source inventory contains a missing file or symbolic link')
    issues = policy.inspect(ROOT, files, require_manifest=True)
    if issues:
        parser.error('Public source boundary failed:\n' + '\n'.join(issues))
    destination.mkdir(parents=True, exist_ok=True)
    for source in files:
        target = destination / source.relative_to(ROOT)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    print(f'Exported {len(files)} reviewed source files to {destination}')

if __name__ == '__main__':
    main()
