#!/usr/bin/env bash
#
# Archive, export, notarise and staple a Release build of DDEVUI.
#
# Usage:
#   scripts/notarise.sh                 full run: archive, export, zip, notarise, staple, assess
#   scripts/notarise.sh --package-only  stop after producing the zip (no credentials needed)
#
# Credentials are never read by this script. It expects a notarytool keychain
# profile called "agilepixel-notary"; see the README for the one-off command
# that creates it.

set -euo pipefail

PROFILE="agilepixel-notary"
SCHEME="DDEVUI"
PROJECT="DDEVUI.xcodeproj"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$REPO_ROOT/build/notarise"
ARCHIVE="$OUT/DDEVUI.xcarchive"
EXPORT_DIR="$OUT/export"
APP="$EXPORT_DIR/DDEVUI.app"
ZIP="$OUT/DDEVUI.zip"

package_only=false
if [[ "${1:-}" == "--package-only" ]]; then
	package_only=true
fi

step() { printf '\n==> %s\n' "$1"; }

if ! $package_only; then
	step "Checking notarytool keychain profile \"$PROFILE\""
	if ! xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
		cat >&2 <<MSG
error: no notarytool keychain profile named "$PROFILE".

Create it once, interactively, with an App Store Connect API key:

  xcrun notarytool store-credentials "$PROFILE" --key /path/to/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --issuer <issuer UUID>

or with an Apple ID and app-specific password:

  xcrun notarytool store-credentials "$PROFILE" --apple-id <email> --team-id M24Q4KZ737

Then rerun this script.
MSG
		exit 1
	fi
fi

step "Cleaning $OUT"
rm -rf "$OUT"
mkdir -p "$OUT"

step "Archiving Release"
xcodebuild -project "$REPO_ROOT/$PROJECT" -scheme "$SCHEME" -configuration Release \
	-destination 'platform=macOS' -archivePath "$ARCHIVE" archive | grep -E 'Signing Identity|error:|ARCHIVE' || true
[[ -d "$ARCHIVE" ]] || { echo "error: archive not produced" >&2; exit 1; }

step "Exporting with Developer ID"
xcodebuild -exportArchive -archivePath "$ARCHIVE" \
	-exportOptionsPlist "$REPO_ROOT/scripts/ExportOptions.plist" -exportPath "$EXPORT_DIR" | grep -E 'error:|EXPORT' || true
[[ -d "$APP" ]] || { echo "error: exported app not found at $APP" >&2; exit 1; }

step "Verifying signature"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Zipping"
ditto -c -k --keepParent "$APP" "$ZIP"
ls -lh "$ZIP"

if $package_only; then
	step "Package only: stopping before notarisation. Zip at $ZIP"
	exit 0
fi

step "Submitting to the notary service (waits for the result)"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

step "Stapling"
xcrun stapler staple "$APP"

step "Gatekeeper assessment"
spctl --assess --type execute --verbose=4 "$APP"

step "Done. Notarised and stapled app at $APP"
