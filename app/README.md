# Ember Vault 2

Ember Vault is a portable, offline-first Rails application built around two capabilities: **Ember**, a local GGUF survival assistant, and **Maps**, shareable offline PMTiles map packs.

There is no Kiwix, ZIM, document archive, RAG, cloud AI, telemetry, or required internet connection at runtime.

## Installation — computer or USB drive

Ember Vault 2 is designed to be self-contained. A finished portable release does **not** require Ruby, Bundler, Node, Homebrew, WSL, Python, CMake, Git, or llama.cpp to be installed on the target computer.

> **Development status:** Ember Vault 2 portable releases are still being validated. Until a release is marked ready, treat generated packages as release candidates rather than finished production downloads.

### Seven setup steps

1. **Download the correct Ember Vault package.** Choose the release for your computer: Windows x64, Linux x64, macOS Intel, or macOS Apple Silicon.

2. **Extract the entire package.** Do not run Ember Vault from inside the ZIP/archive. Extract the whole Ember Vault folder either to a normal folder on the computer or directly onto a USB drive with enough free space for the application, AI models, maps, and saved data.

3. **Keep the folder together.** Do not move individual files out of the Ember Vault folder. The application, bundled runtimes, models, maps, database, settings, logs, and backups use portable paths so the complete folder can be moved together.

4. **Start Ember Vault.** Open the launcher included for your operating system. On Linux, run `portable/start-linux.sh`. Windows and macOS release packages will include their corresponding launcher. Ember Vault starts a local server on your own computer; it does not require a cloud AI service.

5. **Open Ember Vault in your browser.** If it does not open automatically, go to `http://127.0.0.1:3000`. Complete the first-run onboarding screen. The first launch prepares the portable database automatically.

6. **Install your offline content while internet is available.** From Ember Vault, install a supported GGUF AI model and any map packs you want available offline. Models are stored under `storage/models/` and maps under `storage/maps/`. Once the content is installed, normal Ember and map use is intended to work without internet access.

7. **Use or move the installation as one folder.** Shut Ember Vault down before unplugging a USB drive. You can then move the complete Ember Vault folder or USB drive to another supported computer and start it again from its launcher. Your database, settings, models, maps, logs, and backups stay with the portable installation.

### USB setup

For a USB installation, extract the **entire Ember Vault release folder onto the USB drive in Step 2**. Everything writable is kept under that installation's `storage/` directory, so the drive is intended to remain self-contained even when its mount point or drive letter changes.

Allow extra free space for downloaded GGUF models and PMTiles map packs. Do not unplug the drive while Ember Vault is running or while a model/map download is being written.

## Portable data

By default, a portable release keeps mutable data in its own `storage/` directory. Advanced/source installations can set `EMBER_VAULT_DATA_DIR` to another writable directory.

Portable storage contains:

- `models/` — GGUF models
- `maps/` — shareable map-pack directories
- `database/` — application databases
- `settings/`
- `logs/`
- `backups/`
- `tmp/`

## Local AI

Ember uses a persistent `llama-server` process bound to localhost and its OpenAI-compatible chat-completions API. The model is loaded once and reused between questions. The catalog in `config/model_catalog.yml` defines the benchmark candidates. GPU layers default to automatic/full offload; supported CPU execution is used when the GPU path is unavailable.

Override runtime settings with `LLAMA_SERVER_PATH`, `EMBER_VAULT_AI_PROFILE`, `EMBER_VAULT_GPU_LAYERS`, `EMBER_VAULT_AI_THREADS`, and `EMBER_VAULT_AI_TIMEOUT`.

## Map packs

A map pack is a directory under `storage/maps` containing `map-pack.json` and a PMTiles file. Copying a complete pack directory between Ember Vault drives is enough for discovery. See `docs/MAP_PACK_FORMAT.md`.

## Development

The commands below are for developers working from source. Normal portable-release users should follow the seven installation steps above instead.

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

The target release matrix is Windows x64, Linux x64, macOS Intel, and macOS Apple Silicon. A release bundle contains the application, Ruby runtime and gems, llama.cpp runtime, map indexer runtime, and launchers. The launchers use paths relative to the bundle and write mutable state to portable storage.

Release packaging is produced by GitHub Actions. See `docs/PORTABLE_RELEASES.md` for release requirements and validation expectations.

## License

Ember Vault's original source code is available under the MIT License. Models, map data, fonts, and third-party runtimes retain their own licenses.
