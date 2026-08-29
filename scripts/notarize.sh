#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

PROJECT="App/Vocula.xcodeproj"
SCHEME="Vocula"
BUILD_DIR="build/notarize"
KEYCHAIN_PROFILE="${VOCULA_NOTARY_PROFILE:-vocula-notary}"

fail() { echo "❌ $1" >&2; exit 1; }

IDENTITY=$(security find-identity -v -p codesigning \
  | grep "Developer ID Application" | head -1 | sed -E 's/.*"(.*)"/\1/') || true
[ -n "${IDENTITY:-}" ] || fail "No 'Developer ID Application' certificate.
   You have an 'Apple Development' identity, which cannot sign for
   distribution. This needs the paid Apple Developer Program (\$99/year);
   the certificate is issued from the account, not by this script.

   NOTE, because it will surprise you: switching the app from Apple
   Development to Developer ID changes its signature, and macOS binds
   Accessibility and Microphone to (bundle id + signature).
   All three will be revoked on your own Mac and must be granted again."

if [ -n "${VOCULA_NOTARY_KEY:-}" ]; then
  [ -f "$VOCULA_NOTARY_KEY" ] \
    || fail "VOCULA_NOTARY_KEY names no file: $VOCULA_NOTARY_KEY"
  [ -n "${VOCULA_NOTARY_KEY_ID:-}" ] && [ -n "${VOCULA_NOTARY_ISSUER:-}" ] \
    || fail "VOCULA_NOTARY_KEY needs VOCULA_NOTARY_KEY_ID and VOCULA_NOTARY_ISSUER beside it."
  NOTARY=(--key "$VOCULA_NOTARY_KEY" --key-id "$VOCULA_NOTARY_KEY_ID" --issuer "$VOCULA_NOTARY_ISSUER")
else
  NOTARY=(--keychain-profile "$KEYCHAIN_PROFILE")
fi

xcrun notarytool history "${NOTARY[@]}" >/dev/null 2>&1 \
  || fail "notarytool has no usable credentials.
   On this machine, store them once with an app-specific password from
   appleid.apple.com:

     xcrun notarytool store-credentials $KEYCHAIN_PROFILE \\
       --apple-id YOUR@APPLE.ID --team-id YOUR_TEAM_ID --password xxxx-xxxx-xxxx-xxxx

   In CI, set VOCULA_NOTARY_KEY to the path of an App Store Connect .p8, plus
   VOCULA_NOTARY_KEY_ID and VOCULA_NOTARY_ISSUER."

echo "▸ signing identity: $IDENTITY"
rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR"

command -v xcodegen >/dev/null 2>&1 \
  || fail "xcodegen is not installed, and App/Vocula.xcodeproj is generated from
   App/project.yml rather than committed. Install it with: brew install xcodegen"
(cd App && xcodegen generate >/dev/null)

echo "▸ building Release…"
VERSION_OVERRIDE=()
[ -n "${VOCULA_MARKETING_VERSION:-}" ] \
  && VERSION_OVERRIDE=(MARKETING_VERSION="$VOCULA_MARKETING_VERSION")

# A `#` inside a backslash-continued command ends the command, it does not
# comment one line of it: the splice happens first. This one silently cut the
# build off after -derivedDataPath, dropping the signing identity.
# ${A[@]+...}: macOS ships bash 3.2, where an empty array under set -u is unbound.
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$BUILD_DIR/dd" \
  ${VERSION_OVERRIDE[@]+"${VERSION_OVERRIDE[@]}"} \
  CODE_SIGN_IDENTITY="$IDENTITY" \
  CODE_SIGN_STYLE=Manual \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime" \
  build >"$BUILD_DIR/build.log" 2>&1 \
  || { tail -30 "$BUILD_DIR/build.log"; fail "build failed — full log in $BUILD_DIR/build.log"; }

APP="$BUILD_DIR/dd/Build/Products/Release/Vocula.app"
[ -d "$APP" ] || fail "no app at $APP"

plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$APP/Contents/Info.plist"; }
BUILD_NUMBER=$(plist CFBundleVersion)
VERSION=$(plist CFBundleShortVersionString)
COMMITS=$(git rev-list --count --first-parent HEAD)
echo "▸ Version $VERSION ($BUILD_NUMBER)"

[ "$BUILD_NUMBER" = "$COMMITS" ] || fail "CFBundleVersion is $BUILD_NUMBER, but this
   checkout is at $COMMITS commits. scripts/stamp-build-number.sh did not stamp
   the built plist. It bails out quietly in three cases, and its own output is
   in $BUILD_DIR/build.log:
     - the phase is not last (Xcode's Info.plist processing overwrites it),
     - this is not a git checkout,
     - the count passed 9999, CFBundleVersion's four-digit ceiling."

TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || true)
if [ -n "$TAG" ]; then
  [ "$TAG" = "v$VERSION" ] || fail "tag $TAG disagrees with CFBundleShortVersionString
   $VERSION. Raise CFBundleShortVersionString in App/project.yml, or retag."
  echo "▸ tag $TAG agrees with the bundle"
fi

echo "▸ verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "TeamIdentifier|flags" || true

ZIP="$BUILD_DIR/Vocula.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "▸ submitting to Apple (this waits for the verdict)…"
xcrun notarytool submit "$ZIP" "${NOTARY[@]}" --wait \
  || fail "notarisation rejected — read the log with:
   xcrun notarytool log <submission-id> ${NOTARY[*]}"

echo "▸ stapling…"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "▸ Gatekeeper verdict:"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/   /'

ditto -c -k --keepParent "$APP" "$BUILD_DIR/Vocula-notarized.zip"
echo "✅ done: $BUILD_DIR/Vocula-notarized.zip"
echo "   The ticket is stapled to the .app, so it opens with no warning and"
echo "   without a network connection."
