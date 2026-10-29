#!/bin/bash
set -euo pipefail

# Flutter-OH and its plugin graph are isolated from the stable iOS/Android build.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MODE=debug
MODE_SET=false
STAGE_ONLY=false
BUILD_NAME=""
BUILD_NUMBER=""
BUILD_ARGS=(--no-codesign --no-pub)
while (( $# )); do
  case "$1" in
    --debug|--profile|--release)
      if $MODE_SET && [[ "$MODE" != "${1#--}" ]]; then
        printf '%s\n' 'Choose one Harmony build mode: --debug, --profile or --release.' >&2
        exit 2
      fi
      MODE="${1#--}"; MODE_SET=true; shift ;;
    --stage-only) STAGE_ONLY=true; shift ;;
    --build-name|--build-number)
      if (( $# < 2 )); then printf '%s requires a value.\n' "$1" >&2; exit 2; fi
      if [[ "$1" == --build-name ]]; then BUILD_NAME="$2"; else BUILD_NUMBER="$2"; fi
      BUILD_ARGS+=("$1" "$2"); shift 2 ;;
    --build-name=*) BUILD_NAME="${1#*=}"; BUILD_ARGS+=("$1"); shift ;;
    --build-number=*) BUILD_NUMBER="${1#*=}"; BUILD_ARGS+=("$1"); shift ;;
    --codesign|--codesign=*)
      printf '%s\n' 'This script produces a local unsigned HAP. Signing is a separate operation.' >&2
      exit 2 ;;
    --no-codesign|--no-pub) shift ;;
    --help|-h)
      printf '%s\n' \
        'Usage: build_harmony.sh [--debug|--profile|--release] [--stage-only] [flutter build hap options]' \
        'Defaults to debug. Version defaults to pubspec.yaml; --build-name/--build-number override this build only.' \
        'Set FLUTTER_OH_HOME and DEVECO_HOME to the pinned Flutter-OH and API 26+ Command Line Tools.' \
        '--stage-only synchronizes sources and version metadata without resolving packages or building.'
      exit 0 ;;
    *) BUILD_ARGS+=("$1"); shift ;;
  esac
done
: "${FLUTTER_OH_HOME:?Set FLUTTER_OH_HOME to the pinned Flutter-OH SDK}"
: "${DEVECO_HOME:=/Applications/DevEco-Studio.app/Contents}"
export DEVECO_SDK_HOME="${DEVECO_SDK_HOME:-$DEVECO_HOME/sdk}"
if [[ -x "$DEVECO_HOME/tool/node/bin/node" ]]; then
  # The vendor's standalone Command Line Tools use a different layout to the IDE.
  export NODE_HOME="${NODE_HOME:-$DEVECO_HOME/tool/node}"
  TOOLS_HOME="$DEVECO_HOME"
else
  export NODE_HOME="${NODE_HOME:-$DEVECO_HOME/tools/node}"
  TOOLS_HOME="$DEVECO_HOME/tools"
fi
if [[ -z "${JAVA_HOME:-}" && -x "$DEVECO_HOME/jbr/Contents/Home/bin/java" ]]; then
  export JAVA_HOME="$DEVECO_HOME/jbr/Contents/Home"
fi
export PATH="$FLUTTER_OH_HOME/bin:$NODE_HOME/bin:$TOOLS_HOME/ohpm/bin:$TOOLS_HOME/hvigor/bin:$DEVECO_SDK_HOME/default/openharmony/toolchains:$PATH"
EXPECTED=62357a93d653bf844f730bb1f4b7cc9e2139d14e
if [[ "$(git -C "$FLUTTER_OH_HOME" rev-parse HEAD)" != "$EXPECTED" ]]; then
  printf '%s\n' "Use the documented Flutter-OH revision: $EXPECTED" >&2
  exit 1
fi
SDK_METADATA="$DEVECO_SDK_HOME/default/sdk-pkg.json"
if [[ -f "$SDK_METADATA" ]]; then
  API="$(node -e 'process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).data.apiVersion))' "$SDK_METADATA")"
  if [[ "$API" =~ ^[0-9]+$ ]] && (( API < 26 )); then
    printf '%s\n' "This Flutter-OH embedding requires SDK API 26; installed default is API $API. Install a matching free DevEco SDK before building. No framework features were removed." >&2
    exit 2
  fi
fi
WORK="$ROOT/build/harmony-workspace"
mkdir -p "$WORK"
# Flutter's saved `ohos-sdk` takes precedence over DEVECO_SDK_HOME. Give this
# build its own settings directory so a user's IDE SDK cannot select API 22.
export XDG_CONFIG_HOME="$WORK/.flutter-config"
# --delete removes deleted source files, while excluded generated directories stay
# local to this workspace. Never stage machine paths or signing material.
SYNC=(rsync -a --delete --exclude=build/ --exclude=oh_modules/ --exclude=node_modules/
  --exclude=.hvigor/ --exclude=.cxx/ --exclude=.dart_tool/ --exclude=.git/ --exclude=har/
  --exclude=GeneratedPluginRegistrant.ets --exclude=oh-package-lock.json5
  --exclude=local.properties --exclude=key.properties --exclude='*.p12'
  --exclude='*.p7b' --exclude='*.cer' --exclude='*.csr' --exclude='*.keystore' --exclude='*.jks')
for dir in lib assets shaders third_party ohos; do
  mkdir -p "$WORK/$dir"
  "${SYNC[@]}" "$ROOT/$dir/" "$WORK/$dir/"
done
# Only these leaves use OhosView, which upstream Flutter stable does not define.
for leaf in harmony_gallery_save_button.dart; do
  cp "$ROOT/platforms/harmony/$leaf" "$WORK/lib/$leaf"
done
mkdir -p "$WORK/android/app/src/main/cpp" "$WORK/platforms/book_engine"
# Only the shared local-format converter is needed, not Android/JNI or network code.
cp "$ROOT/android/app/src/main/cpp/mobi_export.c" "$WORK/android/app/src/main/cpp/mobi_export.c"
"${SYNC[@]}" "$ROOT/platforms/book_engine/" "$WORK/platforms/book_engine/"
cp "$ROOT/pubspec.yaml" "$WORK/pubspec.yaml"
cp "$ROOT/platforms/harmony/pubspec.lock" "$WORK/pubspec.lock"
cp "$ROOT/platforms/harmony/pubspec_overrides.yaml" "$WORK/pubspec_overrides.yaml"
node "$ROOT/scripts/stage_harmony_metadata.cjs" "$WORK" "$MODE" "$BUILD_NAME" "$BUILD_NUMBER" "$EXPECTED"
printf 'Harmony %s workspace: %s\n' "$MODE" "$WORK"
if $STAGE_ONLY; then exit 0; fi
cd "$WORK"
flutter --suppress-analytics pub get
# Local unsigned artifact only. Signing/distribution is a separate operation.
flutter --suppress-analytics build hap "--$MODE" "${BUILD_ARGS[@]}"
