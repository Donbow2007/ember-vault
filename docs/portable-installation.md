# Portable Ember Vault

Ember Vault can keep the application and its persistent archive on a removable drive. Portable mode does not install a background service or write Ember Vault configuration into the host user's home directory. The host still supplies operating-system dependencies such as Ruby and Poppler.

## Storage layout

The launcher locates the repository containing itself and uses its `data/` directory by default:

```text
ember-vault/
├── start-ember-vault
├── app/ and other application source
├── vendor/                    bundled gems, JavaScript, and optional llama.cpp build
└── data/
    ├── archive_files/         user uploads
    ├── content/               ZIM, document, and PMTiles downloads
    ├── models/                downloaded GGUF models
    ├── backups/               update safety backups
    ├── config/                reserved portable configuration
    ├── logs/                  reserved application logs
    ├── run/                   reserved runtime state
    ├── production.sqlite3     documents, passages, FTS, map names, and settings
    ├── production_cache.sqlite3
    ├── production_queue.sqlite3
    ├── .secret_key_base
    └── ember-vault.log
```

`EMBER_VAULT_DATA_PATH` can select a different data directory. The existing `EMBER_VAULT_DATA_DIR` name remains supported. New file references stored in SQLite are relative to this root. Older `storage/...` references are translated into the selected root, so existing archives do not need a destructive database migration.

Search indexes are not separate host services: full-text search, geographic names, settings, and job state are stored in the SQLite databases under `data/`.

## Host requirements

First-time preparation needs network access and these host tools:

- Ruby 3.3 with Bundler and native build tools
- Git
- SQLite development libraries
- Node.js and npm for map indexing
- Poppler (`pdftoppm`) for PDF page previews
- `zimdump` from zim-tools for ZIM indexing
- CMake and a C/C++ compiler when building the optional local AI runtime

The application, downloaded library, Ruby bundle, browser assets, model files, and databases live on the removable drive. The operating system, device drivers, Ruby interpreter, and shared native libraries remain host dependencies. Ember Vault does not use Docker or a virtual machine.

## Install on Linux or macOS

From an existing Ember Vault checkout, give the installer a new or empty directory on the mounted drive:

```bash
script/install/portable.sh /media/USER/EMBER_VAULT/ember-vault
```

You can also clone the repository directly onto the drive and prepare it:

```bash
git clone https://github.com/Donbow2007/ember-vault.git /media/USER/EMBER_VAULT/ember-vault
cd /media/USER/EMBER_VAULT/ember-vault
./start-ember-vault setup
```

Setup installs the Ruby bundle into `vendor/bundle`, installs the map indexer packages, prepares the databases, builds local assets, and attempts to prepare the optional llama.cpp runtime.

## Install on Windows

In PowerShell, from an existing checkout:

```powershell
.\script\install\portable.ps1 E:\ember-vault
```

To prepare a repository that is already on the drive:

```powershell
Set-Location E:\ember-vault
.\start-ember-vault.ps1 setup
```

`start-ember-vault.cmd` is provided for Command Prompt and double-click use. Windows must have Ruby, Bundler, Git, Node.js, and the optional document tools on `PATH`.

## Start and stop safely

The recommended portable command runs in the foreground:

```bash
./start-ember-vault
```

On Windows:

```powershell
.\start-ember-vault.ps1
```

Open <http://localhost:3000>. Portable mode binds to `127.0.0.1` by default. On a Raspberry Pi that must serve another device on the local network, start it with `BIND_ADDRESS=0.0.0.0`; only do this on a trusted network because Ember Vault does not currently provide user authentication.

Press Ctrl+C and wait for the safe-eject message before unmounting the drive. The runtime stops the web and job processes, checkpoints SQLite WAL files, calls `fsync` for the databases, and asks Unix-like systems to flush buffered filesystem writes.

Background operation remains available:

```bash
./start-ember-vault start
./start-ember-vault status
./start-ember-vault stop
```

Always run `stop` and wait for confirmation before removing a drive used in background mode. No application can prevent corruption if the drive is physically disconnected during a write.

## Moving and backing up the drive

Mount points may change; no mount-specific paths are saved for managed documents or downloads. On another compatible machine, open the mounted application directory and use the same launcher. If the operating system or CPU architecture changed, run `setup` again while online so native Ruby gems and llama.cpp can be rebuilt for that host. The data directory is retained.

For a manual backup, stop Ember Vault and copy the complete `data/` directory to another drive. That directory contains the library, databases, indexes, settings, secret key, and update backups. A future in-app backup/restore workflow can operate on this same boundary.

The portable secret key travels with the drive and is permission-restricted where the filesystem supports Unix permissions. The drive itself is not encrypted. Use operating-system disk encryption if loss of the physical drive is a concern, and keep a recovery copy of the entire data directory.

## Raspberry Pi 3B guidance

- Use a powered USB SSD when possible. Large ZIM archives and PMTiles are a poor fit for low-endurance thumb drives.
- A native Linux filesystem such as ext4 provides stronger SQLite locking and flush semantics than FAT/exFAT. exFAT is convenient across operating systems but offers weaker crash guarantees.
- Keep the defaults of two Rails threads, one job worker, and two AI threads. The cited source assistant requires no model and is the preferred Pi 3B mode.
- llama.cpp and native gems are architecture-specific. An x86 build on the drive will not run on ARM; rerun setup on the Pi.
- Use a stable power supply and shut down Ember Vault before powering off or disconnecting the drive.

A fully bootable Raspberry Pi or PC image is a separate deployment project. It can build on this data-root architecture, but it is not required for portable application data.
