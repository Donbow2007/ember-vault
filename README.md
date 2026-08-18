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
