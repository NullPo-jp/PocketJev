#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-0.1.0}"
BUNDLE_ID="${POCKETJEV_IPA_BUNDLE_ID:-io.github.nullpojp.PocketJev}"
DIST_DIR="$ROOT/dist"
IPA="$DIST_DIR/PocketJev-v${VERSION}.ipa"
SHA="$DIST_DIR/PocketJev-v${VERSION}.sha256"
WORK_ROOT="$(mktemp -d /tmp/PocketJev-ipa.XXXXXX)"
SOURCE_ROOT="$WORK_ROOT/source"
DERIVED_DATA="$WORK_ROOT/DerivedData"
PAYLOAD_ROOT="$WORK_ROOT/package"
APP="$DERIVED_DATA/Build/Products/Release-iphoneos/PocketJev.app"

cleanup() {
  rm -rf "$WORK_ROOT"
}
trap cleanup EXIT

command -v xcodegen >/dev/null 2>&1 || {
  echo "xcodegen is required" >&2
  exit 1
}

mkdir -p "$SOURCE_ROOT" "$PAYLOAD_ROOT/Payload" "$DIST_DIR"

# Build from a neutral temporary path so compiler/runtime diagnostic strings from
# native dependencies do not leak the developer's home directory into the IPA.
/usr/bin/ditto "$ROOT/PocketJev" "$SOURCE_ROOT/PocketJev"
/usr/bin/ditto "$ROOT/PocketJevTests" "$SOURCE_ROOT/PocketJevTests"
/bin/cp "$ROOT/project.yml" "$SOURCE_ROOT/project.yml"

cd "$SOURCE_ROOT"
xcodegen generate

DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
xcodebuild \
  -project "$SOURCE_ROOT/PocketJev.xcodeproj" \
  -scheme PocketJev \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath "$DERIVED_DATA" \
  "PRODUCT_BUNDLE_IDENTIFIER=$BUNDLE_ID" \
  "MARKETING_VERSION=$VERSION" \
  CODE_SIGNING_ALLOWED=NO \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  build

[[ -d "$APP" ]] || {
  echo "Release app not found: $APP" >&2
  exit 1
}

# Keep the entitlement set visible to sideload installers without embedding any
# developer certificate, provisioning profile, team ID, or device registration.
while IFS= read -r nested; do
  /usr/bin/codesign --force --sign - --timestamp=none "$nested"
done < <(find "$APP" -depth \( -name '*.framework' -o -name '*.dylib' \) -print)

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --generate-entitlement-der \
  --entitlements "$SOURCE_ROOT/PocketJev/PocketJev.entitlements" \
  "$APP"

/usr/bin/ditto "$APP" "$PAYLOAD_ROOT/Payload/PocketJev.app"
rm -f "$IPA" "$SHA"
(
  cd "$PAYLOAD_ROOT"
  /usr/bin/zip -qry "$IPA" Payload
)

(
  cd "$DIST_DIR"
  /usr/bin/shasum -a 256 "$(basename "$IPA")" > "$(basename "$SHA")"
)

echo "Created: $IPA"
echo "Created: $SHA"
echo "Bundle ID: $BUNDLE_ID"
echo "Version: $VERSION"
