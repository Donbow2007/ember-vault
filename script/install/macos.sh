#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="${EMBER_VAULT_REPOSITORY:-https://github.com/Donbow2007/ember-vault.git}"
INSTALL_ROOT="${EMBER_VAULT_INSTALL_ROOT:-$HOME/Library/Application Support/Ember Vault}"
APP_ROOT="$INSTALL_ROOT/app"
DATA_ROOT="$INSTALL_ROOT/data"
PLIST_PATH="$HOME/Library/LaunchAgents/com.embervault.server.plist"

if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  if [ -x /opt/homebrew/bin/brew ]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
fi

brew install git llama.cpp node poppler ruby sqlite
brew install libzim || true

mkdir -p "$INSTALL_ROOT" "$DATA_ROOT" "$(dirname "$PLIST_PATH")"
if [ -d "$APP_ROOT/.git" ]; then
  git -C "$APP_ROOT" fetch origin main
  git -C "$APP_ROOT" merge --ff-only origin/main
else
  git clone --branch main "$REPOSITORY_URL" "$APP_ROOT"
fi

if [ ! -L "$APP_ROOT/storage" ]; then
  find "$APP_ROOT/storage" -mindepth 1 -maxdepth 1 ! -name .keep -exec mv -n {} "$DATA_ROOT/" \;
fi

export PATH="$(brew --prefix ruby)/bin:$PATH"
export EMBER_VAULT_DATA_DIR="$DATA_ROOT"
"$APP_ROOT/bin/ember-vault" setup

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.embervault.server</string>
  <key>ProgramArguments</key><array><string>$APP_ROOT/bin/ember-vault</string><string>run</string></array>
  <key>WorkingDirectory</key><string>$APP_ROOT</string>
  <key>EnvironmentVariables</key><dict>
    <key>EMBER_VAULT_DATA_DIR</key><string>$DATA_ROOT</string>
    <key>PATH</key><string>$(brew --prefix ruby)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$DATA_ROOT/launchd.log</string>
  <key>StandardErrorPath</key><string>$DATA_ROOT/launchd.log</string>
</dict></plist>
EOF

launchctl bootout "gui/$(id -u)/com.embervault.server" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
echo "Ember Vault is installed. Open http://localhost:3000"
