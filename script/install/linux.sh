#!/usr/bin/env bash
set -euo pipefail

REPOSITORY_URL="${EMBER_VAULT_REPOSITORY:-https://github.com/Donbow2007/ember-vault.git}"
INSTALL_ROOT="${EMBER_VAULT_INSTALL_ROOT:-$HOME/.local/share/ember-vault}"
APP_ROOT="$INSTALL_ROOT/app"
DATA_ROOT="$INSTALL_ROOT/data"
SERVICE_ROOT="$HOME/.config/systemd/user"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "This installer currently supports Debian, Ubuntu, and Raspberry Pi OS." >&2
  exit 1
fi

sudo apt-get update
sudo apt-get install --no-install-recommends -y build-essential cmake git libsqlite3-dev libyaml-dev nodejs npm pkg-config poppler-utils ruby-dev ruby-full sqlite3
if apt-cache show zim-tools >/dev/null 2>&1; then
  sudo apt-get install --no-install-recommends -y zim-tools
else
  echo "NOTE: zim-tools is unavailable from this distribution; ZIM indexing will remain disabled until zimdump is installed."
fi

mkdir -p "$INSTALL_ROOT" "$DATA_ROOT" "$SERVICE_ROOT"
if [ -d "$APP_ROOT/.git" ]; then
  git -C "$APP_ROOT" fetch origin main
  git -C "$APP_ROOT" merge --ff-only origin/main
else
  git clone --branch main "$REPOSITORY_URL" "$APP_ROOT"
fi

if [ ! -L "$APP_ROOT/storage" ]; then
  find "$APP_ROOT/storage" -mindepth 1 -maxdepth 1 ! -name .keep -exec mv -n {} "$DATA_ROOT/" \;
  rm -f "$APP_ROOT/storage/.keep"
  rmdir "$APP_ROOT/storage"
  ln -s "$DATA_ROOT" "$APP_ROOT/storage"
fi

export EMBER_VAULT_DATA_DIR="$DATA_ROOT"
"$APP_ROOT/bin/ember-vault" setup

cat > "$SERVICE_ROOT/ember-vault.service" <<EOF
[Unit]
Description=Ember Vault offline knowledge server
After=network.target

[Service]
Type=simple
WorkingDirectory=$APP_ROOT
Environment=EMBER_VAULT_DATA_DIR=$DATA_ROOT
Environment=RAILS_MAX_THREADS=2
Environment=JOB_CONCURRENCY=1
ExecStart=$APP_ROOT/bin/ember-vault run
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now ember-vault.service
sudo loginctl enable-linger "$USER" >/dev/null 2>&1 || true

echo "Ember Vault is installed at $APP_ROOT"
echo "Open http://localhost:3000"
echo "Update with: EMBER_VAULT_DATA_DIR=$DATA_ROOT $APP_ROOT/bin/ember-vault update"
