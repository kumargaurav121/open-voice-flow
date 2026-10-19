#!/usr/bin/env bash
# Builds and signs build/Open Voice Flow.app.
#
# Signs with $CODESIGN_IDENTITY, or the first "Apple Development" identity in the keychain
# (a free Apple ID Personal Team is enough). A stable identity and bundle path keep
# macOS permission grants across rebuilds. Ad-hoc signing would reset them every build.
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/Open Voice Flow.app"

identities="$(security find-identity -v -p codesigning | awk -F'"' '/Apple Development/ {print $2}')"
if [[ -z "${CODESIGN_IDENTITY:-}" && $(printf '%s\n' "$identities" | grep -c .) -gt 1 ]]; then
  echo "Several Apple Development identities found; using the first. Set CODESIGN_IDENTITY to pin one," >&2
  echo "since permission grants are tied to the signing team:" >&2
  printf '  %s\n' "$identities" >&2
fi
identity="${CODESIGN_IDENTITY:-$(printf '%s\n' "$identities" | head -1)}"
if [[ -z "$identity" ]]; then
  echo "No Apple Development signing identity found." >&2
  echo "Add your Apple ID in Xcode > Settings > Accounts, or set CODESIGN_IDENTITY." >&2
  exit 1
fi

# MLX's GPU kernels (AI cleanup) are compiled by Xcode's on-demand Metal Toolchain.
if ! xcrun metal -v >/dev/null 2>&1; then
  echo "Xcode's Metal Toolchain is missing. Install it once with:" >&2
  echo "  xcodebuild -downloadComponent MetalToolchain" >&2
  exit 1
fi
# The toolchain is mounted at a path that changes when Xcode updates it, and SwiftPM caches the old one
# ("unable to spawn process .../metal"). Drop the cached build plans when they point elsewhere.
toolchain="$(xcrun -f metal | grep -o 'MetalToolchain-[^/]*' || true)"
plans=".build/out/Intermediates.noindex/XCBuildData"
cached="$( (grep -rhoa 'MetalToolchain-[^/"]*' "$plans" 2>/dev/null || true) | sort -u)"
if [[ -n "$toolchain" && -n "$cached" && "$cached" != "$toolchain" ]]; then
  echo "Metal Toolchain moved since the last build; clearing SwiftPM's cached build plans." >&2
  rm -rf "$plans"
fi

swift build -c "$CONFIG" --product OpenVoiceFlow
bin="$(swift build -c "$CONFIG" --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$bin/OpenVoiceFlow" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
# SwiftPM resource bundles from dependencies.
find "$bin" -maxdepth 1 -name '*.bundle' -exec cp -R {} "$APP/Contents/Resources/" \;

codesign --force --deep --options runtime --timestamp=none \
  --entitlements Resources/OpenVoiceFlow.entitlements \
  --sign "$identity" "$APP"
codesign --verify --strict "$APP"
echo "Built $APP (signed by $identity)"
