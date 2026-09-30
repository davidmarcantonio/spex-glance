#!/bin/sh
# Spex Glance macOS release: archive → Developer ID export → notarize → staple → .dmg → Sparkle sign → appcast.
#
#   scripts/release.sh setup            one-time: Sparkle EdDSA keys + notary credentials
#   scripts/release.sh 0.4.0            build, notarize, package, sign; leaves dist/ ready
#   scripts/release.sh 0.4.0 --publish  also: git tag, GitHub Release, push appcast.xml
#
# Needs: Xcode, xcodegen, gh (brew install gh), a "Developer ID Application" certificate in the
# login keychain (Xcode → Settings → Accounts → Manage Certificates), and `setup` run once.
set -eu
cd "$(dirname "$0")/.."

APP="Spex Glance"
SCHEME="SpexGlance"
REPO_URL="https://github.com/davidmarcantonio/spex-glance"
NOTARY_PROFILE="spex-notary"
SPARKLE_BIN="$(ls -d "$HOME"/Library/Developer/Xcode/DerivedData/SpexGlance-*/SourcePackages/artifacts/sparkle/Sparkle/bin 2>/dev/null | head -1 || true)"

if [ "${1:-}" = "setup" ]; then
  [ -n "$SPARKLE_BIN" ] || { echo "Build once in Xcode first so the Sparkle tools get downloaded."; exit 1; }
  if [ ! -f sparkle-public-key.txt ]; then
    # generate_keys stores the private key in the login Keychain and prints the public key.
    "$SPARKLE_BIN/generate_keys" | grep -Eo '[A-Za-z0-9+/=]{40,}' | head -1 > sparkle-public-key.txt
    echo "Public key written to sparkle-public-key.txt (commit it). Private key is in your Keychain."
    echo "Back the private key up NOW (losing it orphans every installed copy):"
    echo "  $SPARKLE_BIN/generate_keys -x ~/Desktop/spex-sparkle-private.key   → store in your password manager, then delete the file"
  fi
  printf 'Apple ID email: '; read -r APPLE_ID
  TEAM="$(tr -d '[:space:]' < .team)"
  echo "Create an app-specific password at https://account.apple.com → Sign-In and Security → App-Specific Passwords."
  xcrun notarytool store-credentials "$NOTARY_PROFILE" --apple-id "$APPLE_ID" --team-id "$TEAM"
  echo "Done. Run scripts/gen.sh so the public key lands in Info.plist."
  exit 0
fi

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || date +%s)"
DIST="dist"; rm -rf "$DIST"; mkdir -p "$DIST"

# Release notes come from CHANGELOG.md: the "## $VERSION" section, up to the next "## ".
# Markdown for the GitHub Release body; the same text as HTML inside the appcast for Sparkle's sheet.
NOTES_MD="$(awk -v v="$VERSION" '/^## /{p=($2==v)} p&&!/^## /' CHANGELOG.md | sed -e '/./,$!d')"
[ -n "$NOTES_MD" ] || { echo "CHANGELOG.md has no '## $VERSION' section. Write the notes first."; exit 1; }
NOTES_HTML="$(printf '%s\n' "$NOTES_MD" | python3 -c '
import sys, html
out, inlist = [], False
for line in sys.stdin.read().splitlines():
    s = line.strip()
    if s.startswith("- "):
        if not inlist: out.append("<ul>"); inlist = True
        out.append("  <li>" + html.escape(s[2:]) + "</li>")
    else:
        if inlist: out.append("</ul>"); inlist = False
        if s: out.append("<p>" + html.escape(s) + "</p>")
if inlist: out.append("</ul>")
print("\n".join(out))
')"
printf '%s\n' "$NOTES_MD" > "$DIST/notes.md"

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/; s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
scripts/gen.sh

echo "== archive"
xcodebuild -project SpexGlance.xcodeproj -scheme "$SCHEME" -destination 'generic/platform=macOS' \
  -configuration Release -archivePath "$DIST/$APP.xcarchive" archive | grep -E "error:|ARCHIVE" || true

echo "== export (Developer ID)"
TEAM="$(tr -d '[:space:]' < .team)"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>' \
  '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">' \
  '<plist version="1.0"><dict>' \
  '  <key>method</key><string>developer-id</string>' \
  "  <key>teamID</key><string>$TEAM</string>" \
  '  <key>signingStyle</key><string>automatic</string>' \
  '</dict></plist>' > "$DIST/export.plist"
xcodebuild -exportArchive -archivePath "$DIST/$APP.xcarchive" -exportOptionsPlist "$DIST/export.plist" \
  -exportPath "$DIST/export" -allowProvisioningUpdates | grep -E "error:|EXPORT" || true

echo "== notarize app"
ditto -c -k --keepParent "$DIST/export/$APP.app" "$DIST/notarize.zip"
xcrun notarytool submit "$DIST/notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DIST/export/$APP.app"

echo "== dmg"
DMG="$DIST/SpexGlance-$VERSION.dmg"
STAGE="$DIST/dmg"; mkdir -p "$STAGE"
cp -R "$DIST/export/$APP.app" "$STAGE/"
cp LICENSE "$STAGE/LICENSE.txt"          # MIT text travels with the binary
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
codesign --force --sign "Developer ID Application" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait >/dev/null
xcrun stapler staple "$DMG"

echo "== sparkle signature + appcast"
SIG="$("$SPARKLE_BIN/sign_update" "$DMG")"     # → sparkle:edSignature="..." length="..."
DL="$REPO_URL/releases/download/v$VERSION/SpexGlance-$VERSION.dmg"
NOTES="$REPO_URL/releases/tag/v$VERSION"
DATE="$(date -R)"
[ -f appcast.xml ] || printf '%s\n' \
  '<?xml version="1.0" encoding="utf-8"?>' \
  '<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">' \
  '  <channel>' \
  '    <title>Spex Glance</title>' \
  '  </channel>' \
  '</rss>' > appcast.xml
ITEM="    <item>
      <title>Spex Glance $VERSION</title>
      <link>$NOTES</link>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <pubDate>$DATE</pubDate>
      <description><![CDATA[
$NOTES_HTML
      ]]></description>
      <enclosure url=\"$DL\" $SIG type=\"application/octet-stream\" />
    </item>"
# newest first, right after the channel title
ITEM="$ITEM" perl -0pi -e 's|(<title>Spex Glance</title>\n)|$1$ENV{ITEM}\n|' appcast.xml

echo "Built $DMG"
if [ "$PUBLISH" = "--publish" ]; then
  git add project.yml appcast.xml CHANGELOG.md
  git commit -m "Release $VERSION" || true
  git tag -a "v$VERSION" -m "Spex Glance $VERSION"
  git push && git push --tags
  gh release create "v$VERSION" "$DMG" --title "Spex Glance $VERSION" --notes-file "$DIST/notes.md"
  echo "Published. Sparkle clients see $VERSION on their next check (daily, or Check for Updates…)."
fi
