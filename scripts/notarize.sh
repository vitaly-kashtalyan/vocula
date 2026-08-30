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
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
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

# `git describe --exact-match` returns the lexicographically smallest of the
# tags on a commit, so a retry after a failed release — which leaves the first
# tag behind — compared the OLD tag against the NEW version and could never
# pass. Asking whether the expected tag is present has no ordering to get wrong.
TAGS=$(git tag --points-at HEAD)
if [ -n "$TAGS" ]; then
  printf '%s\n' "$TAGS" | grep -qFx "v$VERSION" || fail "HEAD carries \
$(printf '%s' "$TAGS" | tr '\n' ' ')— but not v$VERSION, which is what this build stamped.
   Raise MARKETING_VERSION in App/project.yml, or tag v$VERSION.
   CFBundleShortVersionString is \$(MARKETING_VERSION) and must stay a substitution."
  echo "▸ tag v$VERSION is on this commit"
fi

echo "▸ verifying signature…"
codesign --verify --deep --strict --verbose=2 "$APP" 2>&1 | tail -3
codesign -dv --verbose=4 "$APP" 2>&1 | grep -E "TeamIdentifier|flags" || true

# The ticket is fetched for what was SUBMITTED and written into what is
# SHIPPED, and for the app those are different files: stapler refuses a zip.
notarise() {
    local submit="$1" staple="$2" log="$BUILD_DIR/notarytool-$3.txt"
    xcrun notarytool submit "$submit" "${NOTARY[@]}" --wait 2>&1 | tee "$log"
    local submission
    submission=$(grep -E "^ *id: " "$log" | head -1 | sed -E 's/.*id: //')
    grep -qE "^ *status: Accepted" "$log" || fail "Apple refused $(basename "$submit") \
($(grep -E '^ *status: ' "$log" | tail -1 | sed -E 's/.*status: //')).
   Read what it objected to:
   xcrun notarytool log $submission ${NOTARY[*]}"
    xcrun stapler staple "$staple"
    xcrun stapler validate "$staple"
}

# notarytool submit exits 0 even when Apple refuses, so the status decides.
# Trusting the exit code sent a rejected build to stapler, which then failed
# with "Record not found" and named nothing about why.
echo "▸ submitting the app (this waits for the verdict)…"
ditto -c -k --keepParent "$APP" "$BUILD_DIR/submission.zip"
notarise "$BUILD_DIR/submission.zip" "$APP" app

echo "▸ Gatekeeper verdict on the app:"
spctl --assess --type execute --verbose=2 "$APP" 2>&1 | sed 's/^/   /'

ZIP="$BUILD_DIR/Vocula.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

DMG="$BUILD_DIR/Vocula.dmg"
echo "▸ building the disk image…"
./scripts/make-dmg.sh "$APP" "$DMG"

# The ticket inside the .app does not cover the image carrying it, so the image
# is a second submission with a staple of its own. Without it Gatekeeper has to
# ask Apple about the image over the network before the user may open it.
echo "▸ submitting the disk image…"
notarise "$DMG" "$DMG" dmg

echo "▸ Gatekeeper verdict on the image:"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG" 2>&1 | sed 's/^/   /'

echo "✅ done:"
echo "   $DMG"
echo "   $ZIP"
echo "   Both carry their own ticket, so they open with no warning and with no"
echo "   network connection."
