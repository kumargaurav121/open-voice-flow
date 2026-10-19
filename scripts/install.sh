#!/usr/bin/env bash
# Checks everything Open Voice Flow needs, builds it, installs it to ~/Applications and launches it.
# Safe to run again: it rebuilds and replaces the installed copy (models and settings are kept).
#
#   scripts/install.sh
#
# Stops at the first problem with the exact fix. Never uses sudo; prints the sudo command when one is
# needed. After launch, the app's setup window takes over (permissions, model download, first compile).
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/Open Voice Flow.app"
DEST="$HOME/Applications/Open Voice Flow.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

ok() { printf '  ✓ %s\n' "$1"; }
step() { printf '\n%s\n' "$1"; }
# fail "problem" "fix line" ...
fail() {
  printf '  ✗ %s\n' "$1" >&2
  shift
  printf '      %s\n' "$@" >&2
  exit 1
}

step "Checking this Mac"
[[ "$(sysctl -n hw.optional.arm64 2>/dev/null || echo 0)" == 1 ]] \
  || fail "Needs an Apple Silicon Mac (M1 or later)." "The speech models run on the Neural Engine and GPU of Apple Silicon."
ok "Apple Silicon"

macos="$(sw_vers -productVersion)"
(( ${macos%%.*} >= 14 )) || fail "Needs macOS 14 Sonoma or later (this Mac has $macos)." "Update in System Settings → General → Software Update."
ok "macOS $macos"

free_gb="$(df -g "$HOME" | awk 'NR==2 {print $4}')"
(( free_gb >= 20 )) || fail "Needs about 20 GB free (${free_gb} GB free): ~7 GB of models plus the build." "Free up space, then run this again."
ok "${free_gb} GB free"

step "Checking Xcode"
developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ "$developer_dir" != *Xcode*.app* ]]; then
  if [[ -d /Applications/Xcode.app ]]; then
    fail "Xcode is installed but not selected (using: ${developer_dir:-nothing})." \
      "Run: sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"
  fi
  fail "Full Xcode is needed (Command Line Tools alone can't build the app)." \
    "1. Install Xcode from the App Store: https://apps.apple.com/app/xcode/id497799835" \
    "2. Open it once and let it finish installing components." \
    "3. Run this script again."
fi
xcodebuild -license check >/dev/null 2>&1 \
  || fail "Xcode's license hasn't been accepted." "Run: sudo xcodebuild -license accept"
ok "$(xcodebuild -version | head -1)"

if ! xcrun metal -v >/dev/null 2>&1; then
  echo "  … Downloading Xcode's Metal Toolchain (once, about 1 GB)"
  xcodebuild -downloadComponent MetalToolchain
  xcrun metal -v >/dev/null 2>&1 || fail "The Metal Toolchain didn't install." "Run: xcodebuild -downloadComponent MetalToolchain"
fi
ok "Metal Toolchain"

if [[ -z "${CODESIGN_IDENTITY:-}" ]] && ! security find-identity -v -p codesigning | grep -q "Apple Development"; then
  fail "No code-signing certificate. The app is signed with your own free Apple ID, so macOS keeps its permissions." \
    "1. Open Xcode → Settings (⌘,) → Accounts." \
    "2. Click + → Apple ID, and sign in with your Apple ID (free; no paid developer account needed)." \
    "3. Select your account → Manage Certificates… → + → Apple Development → Done." \
    "4. Run this script again."
fi
ok "Signing certificate"

step "Building (the first build takes several minutes)"
scripts/build-app.sh

step "Installing to ~/Applications"
pkill -x OpenVoiceFlow 2>/dev/null && sleep 1 || true
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$APP" "$DEST"
"$LSREGISTER" -f "$DEST"
ok "$DEST"
open "$DEST"
ok "Launched. Look for the wave icon in the menu bar."

cat <<'EOF'

On a first install the setup window opens (reopen it any time: menu bar icon → Setup Guide…):
  1. Allow Microphone, Accessibility and Input Monitoring (each row ticks once allowed).
  2. Download the models (about 6.5 GB, pinned and checksum-verified).
  3. Wait for the one-time "Preparing" step (up to ~15 minutes the first time).
  4. Try a dictation: hold fn, speak, let go.
Tip: set System Settings → Keyboard → "Press 🌐 key to" → "Do Nothing", so fn doesn't open the emoji picker.
EOF
