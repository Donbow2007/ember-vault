# Ember Vault 2

Ember Vault is a portable, offline-first Rails application built around two capabilities: **Ember**, a local GGUF survival assistant, and **Maps**, shareable offline PMTiles map packs.

There is no Kiwix, ZIM, document archive, RAG, cloud AI, telemetry, or required internet connection at runtime.

## Portable data

Set `EMBER_VAULT_DATA_DIR` to the writable directory on the portable drive. Ember Vault keeps mutable data under:

- `models/` — GGUF models
- `maps/` — shareable map-pack directories
- `database/` — application databases
- `settings/`
- `logs/`
- `backups/`
- `tmp/`

## Local AI

Ember uses a persistent `llama-server` process bound to localhost and its OpenAI-compatible chat-completions API. The model is loaded once and reused between questions. The catalog in `config/model_catalog.yml` defines the benchmark candidates. GPU layers default to automatic/full offload; llama.cpp falls back to supported CPU execution when a GPU backend is unavailable.

Override runtime settings with `LLAMA_SERVER_PATH`, `EMBER_VAULT_AI_PROFILE`, `EMBER_VAULT_GPU_LAYERS`, `EMBER_VAULT_AI_THREADS`, and `EMBER_VAULT_AI_TIMEOUT`.

## Map packs

A map pack is a directory under `storage/maps` containing `map-pack.json` and a PMTiles file. Copying a complete pack directory between Ember Vault drives is enough for discovery. See `docs/MAP_PACK_FORMAT.md`.

## Development

```bash
bundle install
npm ci --prefix vendor/map_indexer
bin/rails db:prepare
bin/rails server
bin/jobs
```

Verification:

```bash
bin/rails test
bin/rubocop
bin/brakeman
```

## Portable releases

The target release matrix is Windows x64, Linux x64, macOS Intel, and macOS Apple Silicon. A release bundle contains the application, Ruby runtime and gems, llama.cpp runtime, map indexer runtime, and launchers. The launchers use only paths relative to the bundle and write mutable state to the portable data directory.

The source-tree launchers under `portable/` remain useful for development. Release packaging is produced by GitHub Actions.

## License

Ember Vault's original source code is available under the MIT License. Models, map data, fonts, and third-party runtimes retain their own licenses.
