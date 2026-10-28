#!/usr/bin/env node
'use strict';

const fs = require('node:fs');
const path = require('node:path');

const [workspace, mode, requestedName, requestedNumber, flutterRevision] = process.argv.slice(2);
const pubspec = fs.readFileSync(path.join(workspace, 'pubspec.yaml'), 'utf8');
const version = pubspec.match(/^version:\s*['"]?([^\s'"#]+)['"]?\s*(?:#.*)?$/m)?.[1];
if (!version) throw new Error('pubspec.yaml must declare the application version.');
const [defaultName, defaultNumber = '1'] = version.split('+');
const name = requestedName || defaultName;
const number = requestedNumber || defaultNumber;
if (!/^\d+\.\d+\.\d+(?:\.\d+)?$/.test(name)) {
  throw new Error('Harmony build-name must have three or four numeric components.');
}
if (!/^[1-9]\d*$/.test(number) || !Number.isSafeInteger(Number(number))) {
  throw new Error('Harmony build-number must be a positive integer.');
}
const manifestPath = path.join(workspace, 'ohos/AppScope/app.json5');
const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
manifest.app.versionName = name;
manifest.app.versionCode = Number(number);
fs.writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + '\n');
fs.writeFileSync(path.join(workspace, 'harmony-build.json'), JSON.stringify({
  mode,
  versionName: name,
  versionCode: Number(number),
  sourceVersion: version,
  flutterRevision,
  codesign: false,
}, null, 2) + '\n');
