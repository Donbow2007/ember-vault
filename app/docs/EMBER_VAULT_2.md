# Ember Vault 2 portable direction

Ember Vault 2 keeps Rails, offline maps, and local llama.cpp inference while
removing the assumption that a large document preprocessing library is required.

## Portable storage contract

All mutable data belongs under `EMBER_VAULT_DATA_DIR`. When unset, it defaults
to `storage/` inside the Ember Vault checkout. A USB distribution should launch
with this directory on the USB, so downloaded maps, models, SQLite databases,
logs, indexes, and backups travel with the drive.

## AI runtime

The same GGUF can run on CPU or use llama.cpp GPU acceleration when the bundled
platform runtime supports it. Ember Vault requests maximum GPU offload by
default; llama.cpp leaves unsupported work on CPU. Set
`EMBER_VAULT_GPU_LAYERS=0` to force CPU-only mode or a number to cap offload.

Model binaries do not belong in Git. `config/model_catalog.yml` is the small,
versioned manifest used to track benchmark candidates and, once verified, their
upstream download/checksum metadata.

## Maps

PMTiles and the geographic search index remain core Ember Vault functionality.
Map downloads must resolve beneath the portable data directory before the
portable release is considered complete.

## Packaging target

Release bundles should eventually contain platform-specific Ruby/gems and
llama.cpp binaries for Windows x64, Linux x64, macOS x64, and macOS arm64.
Launchers select the matching runtime; users should not need Ruby, WSL, Node,
or llama.cpp installed globally.
