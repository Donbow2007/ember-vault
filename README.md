# Ember Vault

Ember Vault is a Rails 8, offline-first knowledge vault for preserving, indexing, searching, and reading survival information when an internet connection is unavailable.

It downloads approved Kiwix ZIM archives, public full-text books, and PMTiles maps during setup or explicit discovery. Once content is stored, the document reader, full-text search, map viewer, geographic search, and interface assets run locally.

## Features

- Full-text SQLite FTS5 search across indexed document passages
- Exact source passage navigation with PDF page rendering and ZIM source assets
- Offline MapLibre and PMTiles maps with locally bundled fonts
- Geographic indexing for cities, towns, roads, water, and landmarks
- Address-style and fuzzy map search
- Topic discovery for bundled Kiwix options and public Open Library books
- Background download queue with live progress, stop, retry, delete, and reindex controls
- Persistent light and dark themes
- Optional lightweight offline-AI setup profiles
- No telemetry or CDN/browser runtime dependencies

## Requirements

- Ruby 3.3.8
- Rails 8.0.5.1
- SQLite 3 with FTS5
- Node.js and npm for the PMTiles geographic indexer
- `zimdump` from `zim-tools` for reading and indexing ZIM archives
- `pdftoppm` from Poppler for PDF page previews

## Setup

```bash
bin/setup
npm install --prefix vendor/map_indexer
bin/rails db:prepare
```

Start the web server and background job runner in separate terminals:

```bash
bin/rails server
bin/jobs
```

Open <http://localhost:3000>. Browser geolocation works on localhost; remote deployments normally require HTTPS.

## Automated installation

Ember Vault includes installers that provision dependencies, prepare the production databases and assets, register a background service, and start the application.

Raspberry Pi OS, Debian, or Ubuntu:

```bash
git clone https://github.com/Donbow2007/ember-vault.git
cd ember-vault
script/install/linux.sh
```

macOS:

```bash
git clone https://github.com/Donbow2007/ember-vault.git
cd ember-vault
script/install/macos.sh
```

Windows PowerShell:

```powershell
git clone https://github.com/Donbow2007/ember-vault.git
cd ember-vault
powershell -ExecutionPolicy Bypass -File script/install/windows.ps1
```

The Raspberry Pi target is a Pi 3 Model B running 64-bit Raspberry Pi OS Lite. Native Windows ZIM indexing additionally requires `zimdump` on `PATH`; PDF, text, map, search, and source-assistant features do not depend on it.

## Updates and recovery

Open **System** in the application to check GitHub and queue an update. Installation is restricted to requests made from the Ember Vault device unless `ALLOW_REMOTE_UPDATES=1` is deliberately configured.

The command-line equivalent is:

```bash
bin/ember-vault update
```

The updater:

- refuses to overwrite tracked local source changes;
- accepts only a fast-forward update from `origin/main`;
- stops a launcher-managed server before copying databases;
- backs up every SQLite database under `storage/backups`;
- installs dependencies, prepares databases, and precompiles assets;
- restarts the server and verifies the local `/up` health endpoint;
- restores the prior Git revision and database backup after a failed health check.

Downloaded archives, imported documents, maps, indexes, secrets, logs, and databases remain under the ignored storage directory and are never pulled from or pushed to GitHub.

Runtime commands:

```bash
bin/ember-vault setup
bin/ember-vault start
bin/ember-vault stop
bin/ember-vault restart
bin/ember-vault status
bin/ember-vault update
```

Automatic update checks require temporary access to `api.github.com` and update installation requires `github.com`. All archive reading, search, maps, and Field Intel remain offline.

## Verification

```bash
bin/rails test
bin/rubocop
bin/brakeman
```

## Offline and network boundaries

The browser runtime loads assets only from Ember Vault itself. External network access is limited to explicit setup, catalog discovery, and download operations performed by the Rails server. Download origins are allowlisted and checked against private-network addresses.

Downloaded archives, imported documents, generated indexes, databases, logs, credentials, and compiled assets are intentionally excluded from Git.

## Content and attribution

Catalog snapshots are derived from Project NOMAD manifests. Map data is attributed to OpenStreetMap contributors. Downloaded works retain their own licenses and terms. See [ATTRIBUTION.md](ATTRIBUTION.md) for details.

## Status

Ember Vault is under active development. Review storage requirements and content licenses before distributing downloaded material.

## License

Ember Vault's original source code is available under the [MIT License](LICENSE). Bundled libraries, fonts, catalog metadata, maps, and downloaded works retain their respective licenses.
