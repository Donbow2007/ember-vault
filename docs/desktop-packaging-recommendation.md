# Ember Vault desktop packaging recommendation

## Decision

Keep the Rails 8 application and its server-rendered interface. For Windows,
macOS, and normal desktop Linux, prototype a **Tauri 2 shell** that owns a
bundled Ember Vault backend process. Do not rewrite the Rails UI.

Electron can perform the same job and is a reasonable fallback if system
webview differences become unmanageable. It is not the first choice because
it embeds Chromium and Node in every installation and adds too much memory and
storage overhead for Ember Vault's low-resource goal. Electron itself describes
that embedded architecture in its [introduction](https://www.electronjs.org/docs/latest/).

For a Raspberry Pi 3 B, retain the native Rails launcher and open Ember Vault
in the Pi's existing browser, or serve it to another device on a trusted local
network. A second desktop browser engine is the wrong tradeoff on a 1 GB Pi.

This is a packaging decision, not a stack migration.

## What runs today

`bin/ember-vault` delegates setup, start, stop, restart, status, and update to
`EmberVault::Runtime`.

Setup currently does all of the following:

- checks or installs Ruby gems;
- installs the PMTiles indexer's npm packages;
- builds or locates `llama-completion` when optional model answers are enabled;
- prepares the Rails databases; and
- precompiles Rails assets.

Production startup launches one Puma/Rails server. Puma's Solid Queue plugin
also starts the queue supervisor and its single configured worker, which handles
downloads, document/ZIM/map indexing, updates, and optional AI responses. These
are child processes, not separately installed operating-system services.
SQLite FTS5 search, geographic search, cache state, and queue state do not need
PostgreSQL, Redis, Elasticsearch, or another server.

The existing runtime already provides useful desktop foundations: a PID record,
process-group shutdown on Unix, `/up` health polling, bounded worker counts,
SQLite WAL checkpointing, database `fsync`, and a configurable data root.

## What an installer must bundle

A release build must be produced independently for each supported operating
system and CPU architecture. It should contain only production material:

- a compatible Ruby 3.3 runtime and standard library;
- the Rails application and production gems (`bundle install --without
  development test` into a release-owned bundle);
- precompiled Propshaft/importmap assets;
- the SQLite library/native gem with FTS5 enabled;
- `zimdump` and its required libzim libraries;
- Poppler's `pdftoppm` and required libraries;
- the PMTiles indexer script, its three npm dependencies, and a small bundled
  Node runtime for the first release;
- an architecture-specific, slim `llama-completion` runtime when model support
  is included; and
- the desktop shell, icons, licenses, and release metadata.

Bundler, npm, Git, CMake, compilers, headers, llama.cpp source, tests, and
development gems must stay in the build environment. They must not run on an
end user's computer. GGUF models and downloaded library/map content remain
optional user data rather than inflating every installer.

The current repository contains a Linux x86-64-only `zimdump` bundle and an
x86-64 Linux llama.cpp build. Those cannot be copied into Windows, macOS, or
ARM packages. `pdftoppm` is currently discovered on `PATH`, and map indexing
currently invokes `node` on `PATH`. Release packaging must provide explicit
per-platform paths for all three instead of depending on the user's machine.

Tauri supports packaged external executables with a binary per target triple,
which matches this sidecar-heavy design. Its
[sidecar documentation](https://v2.tauri.app/develop/sidecar/) specifically
requires architecture-suffixed binaries and supports launching them without
asking the user to install their runtime.

## Desktop shell lifecycle

The shell should implement this sequence:

1. Acquire a single-instance application lock. A second launch focuses the
   existing window rather than starting another Rails or queue process.
2. Resolve the platform's application-data directory and set
   `EMBER_VAULT_DATA_PATH` before Ruby starts.
3. Choose an unused loopback port, set a per-launch secret, and start a small
   platform-specific backend launcher. The launcher then starts the bundled
   Ruby with `bin/ember-vault run`.
4. Bind Rails to `127.0.0.1`, never `0.0.0.0`, for desktop mode. Show a branded
   local splash/progress window while polling `/up`.
5. Navigate the same webview to the local Rails URL only after it is healthy.
   If startup fails, show a plain-language recovery screen with Retry, Open Log,
   and Quit buttons.
6. Restrict the webview to the chosen loopback origin. Open only explicitly
   approved external links in the operating system browser, and deny unexpected
   navigation, popups, and permissions.
7. On application quit, ask the backend launcher for graceful shutdown, stop
   accepting new work, terminate Puma/Solid Queue, checkpoint all SQLite WAL
   files, flush them, and wait up to 15 seconds before force-killing the process
   tree. Window close may hide the window on macOS, but an actual app quit must
   stop the backend. A future tray mode must make continued background operation
   explicit.

On Windows, the launcher should place the full backend tree in a Job Object so
Puma, Solid Queue, map indexing, `zimdump`, `pdftoppm`, and llama.cpp cannot be
orphaned. On Unix, retain process groups. The PID file should become a secondary
diagnostic; the desktop single-instance lock is authoritative.

The Rails process should receive an unguessable per-launch token so another
local process cannot drive desktop-only shutdown or maintenance endpoints.
Ember Vault currently has no user authentication, which makes loopback-only
binding and strict webview navigation mandatory.

If Electron is used instead, its main process can own this exact lifecycle and
display Rails in a `BrowserWindow`. Keep `nodeIntegration` disabled, context
isolation and renderer sandboxing enabled, and expose no generic process or
filesystem IPC. Electron's [security checklist](https://www.electronjs.org/docs/latest/tutorial/security)
also calls for restricted navigation/windows and current framework releases.

## Resource impact

The following are planning ranges, not guarantees; the release prototype must
be measured on each target:

| Shell | Additional idle RAM | Idle CPU | Shell storage before Ember Vault runtime |
| --- | ---: | ---: | ---: |
| Electron | about 120-250 MB | normally under 1%, with Chromium wakeups | current upstream compressed binaries are roughly 116-138 MB; commonly 250-400 MB unpacked |
| Tauri/system webview | about 30-100 MB | normally near 0% | often a few MB for the shell; Windows offline WebView2 can add about 127 MB |
| Existing system browser launcher | no second browser engine | normally near 0% beyond Rails | negligible launcher overhead |

Electron uses multiple Chromium processes by design; see its
[process model](https://www.electronjs.org/docs/latest/tutorial/process-model).
The current Electron 43 release artifacts provide the package-size reference
in the [official releases](https://github.com/electron/electron/releases/tag/v43.3.0).
Electron 44 also ends published Linux 32-bit ARM builds, making it a poor
long-term Raspberry Pi 3 choice; see Electron's
[planned breaking changes](https://www.electronjs.org/docs/latest/breaking-changes/).

Tauri uses the operating system's native webview rather than bundling a browser;
its project reports that a minimal shell can be under 600 KB. Ember Vault will
be much larger because Ruby and native readers must still be bundled. See
[What is Tauri?](https://tauri.app/start/).

The Rails backend, indexes, and content dominate Ember Vault's actual workload.
The shell does not make ZIM/map indexing or model inference cheaper. On a Pi 3,
continue with two Rails threads, one job worker, and source-assistant mode by
default. Avoid Electron entirely there.

## Application files and persistent data

Installed application files should be immutable and replaceable. Persistent
data should use one root outside the application directory:

- Windows: `%LOCALAPPDATA%\EmberVault\data`
- macOS: `~/Library/Application Support/Ember Vault/data`
- Linux: `${XDG_DATA_HOME:-~/.local/share}/ember-vault/data`

That root contains the three production SQLite databases and their WAL files,
`archive_files/` imports, `content/` downloads, `models/`, `backups/`, `config/`,
`logs/`, `run/`, the local secret, and generated indexes. Existing
`EmberVault::Paths` support and relative stored paths already provide the needed
separation. The wrapper must set the data-root environment before loading the
runtime because its path constants are initialized when Ruby loads the class.

The default uninstaller behavior must be **remove the application and preserve
my vault**. It removes the shell, Rails code, bundled runtimes, shortcuts, and
temporary files but leaves the data root untouched. Full deletion should be a
separate, strongly confirmed action that shows the exact path and estimated
size first. It may delete only the Ember Vault data root. Imported files are
copied into `archive_files/`; source files elsewhere on the computer must never
be deleted.

## Updates

The current Git updater is appropriate for developer/source installations, not
signed desktop releases. Desktop releases should update the complete signed
application package while preserving the data root:

1. download and verify signed release metadata and the platform/architecture
   package;
2. stop new background work;
3. checkpoint and back up every SQLite database;
4. replace immutable application files;
5. run packaged migrations with the new runtime;
6. health-check the new backend; and
7. retain the old app package and database snapshot until success is confirmed.

Automatic checks must be opt-in and fail harmlessly while offline. A visible
Check for Updates action is the reliable air-gapped default. Electron supports
Windows/macOS updating but has no built-in Linux updater, where the distribution
package manager is recommended; see the
[Electron updater documentation](https://www.electronjs.org/docs/latest/api/auto-updater/).

## Platform packages

### Windows

Build and test x86-64 first, then ARM64 separately. Use a per-user NSIS installer
so normal installation needs no administrator rights. Bundle the WebView2
offline installer for a truly self-contained installer; a smaller online build
may rely on the Evergreen runtime already present on supported Windows versions.
Tauri documents NSIS/MSI output and estimates about 127 MB for the offline
WebView2 option in its [Windows installer guide](https://v2.tauri.app/distribute/windows-installer/).
Code-sign the installer and every shipped executable. Use a Windows-native Ruby,
native gems, Poppler, zim-tools/libzim, Node, and optional llama.cpp build.

### macOS

Produce separate Apple Silicon and Intel application bundles, then a signed DMG
for each (or a tested universal package containing both native dependency sets).
Sign the outer app and every bundled Ruby/native helper, enable hardened runtime,
notarize, and staple the ticket. Apple documents those requirements in
[Notarizing macOS software](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
Use the system WKWebView. Do not assume Homebrew or a shell `PATH` exists.

### Linux desktop

Build x86-64 and ARM64 separately on the oldest supported distribution baseline.
Start with `.deb` for Debian/Ubuntu/Raspberry Pi OS-family systems and AppImage
for a broader portable desktop trial; add RPM only after the runtime bundle is
stable. Tauri warns that AppImage compatibility depends on the build baseline,
grows a small app to 70+ MB, and that ARM AppImages must be built on ARM or under
emulation in its [AppImage guide](https://v2.tauri.app/distribute/appimage/).

### Raspberry Pi / ARM Linux

A Pi 3 B can run a 64-bit OS despite its limited memory, but both Ruby native
extensions and every helper require ARM64 builds. The recommended Pi product is
an appliance-style `.deb` or image that installs a desktop icon when a desktop
exists and otherwise starts Rails through the existing launcher for access from
another device. If network access is enabled, authentication and an explicit
trusted-network setup step are required before this can be a safe consumer
default.

## Portable USB implications

The current configurable data root and relative database paths are the correct
foundation. A portable release should place replaceable app/runtime files and a
`data/` directory on the drive, set the data root before startup, retain the safe
shutdown/checkpoint flow, and never write user data to a host profile by default.

Portable does not mean one executable works everywhere. The drive needs a
separate signed runtime directory for each supported OS/architecture, or the
user downloads the matching portable package. Native helpers and Ruby gems make
that unavoidable. SQLite reliability and safe eject behavior must be tested on
the intended filesystem; ext4/APFS/NTFS are safer than exFAT for active
databases. A powered external SSD is preferred to a flash drive.

Tauri remains suitable for portable desktop packages, but Windows WebView2
availability must be handled. Electron is more self-contained on a random host,
but its size and RAM cost remain. Keep the backend-wrapper protocol shell-neutral
so either can launch the same packaged Rails runtime.

## Android direction

Do not try to ship the desktop Ruby/Puma process tree unchanged on Android.
Android would need platform-specific implementations for lifecycle, storage
permissions, background work, PDF rendering, ZIM reading, maps, and optionally
llama.cpp. Tauri can target mobile, but the current ERB interface depends on a
live Rails backend and therefore is not automatically a reusable mobile
frontend.

The shareable contract should be the vault format rather than the desktop
runtime:

- versioned SQLite schema and FTS/tokenization rules;
- relative content paths;
- unchanged ZIM, PDF/text, PMTiles, and GGUF files;
- a versioned manifest describing files, hashes, schema version, and indexes;
- explicit import/export and migration rules; and
- a consistent stable content identifier independent of database row IDs.

Android can use native MapLibre/PMTiles, PDF, libzim, SQLite/FTS, and model
libraries while remaining compatible with desktop vault packages. Do not allow
desktop and Android to open the same SQLite files concurrently; exchange a
stopped, checkpointed snapshot or a defined export package.

## Main risks and required prototype

The major blockers are platform packaging, not the Rails UI:

- the repository's ZIM and llama.cpp binaries are Linux x86-64 specific;
- PDF and Node executables are still resolved from host `PATH`;
- Ruby plus native gems must be built and tested per platform/architecture;
- Windows process-tree shutdown needs a Job Object rather than Unix signals;
- current desktop startup defaults to `0.0.0.0` unless the launcher overrides
  it;
- source-install Git updates must be separated from signed desktop updates;
- there is no authentication if a Pi/network package exposes Rails; and
- installers must inventory third-party licenses for Ruby, libzim/zim-tools,
  Poppler, Node packages/runtime, llama.cpp, fonts, and other bundled assets.

The next implementation should be a time-boxed x86-64 Linux Tauri prototype
that bundles Ruby and production gems, starts on a random loopback port, opens
the existing Rails UI, prevents a second instance, and proves clean shutdown.
It should record cold-start time, total process-tree RAM/CPU, installed size,
map/ZIM/PDF indexing, a long download interrupted by Quit, and database recovery
after a forced kill. Only after that passes should the same release manifest be
built on Windows and macOS CI runners.
