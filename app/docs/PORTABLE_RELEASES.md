# Portable releases

Ember Vault 2 targets four self-contained desktop bundles:

- Windows x64
- Linux x64
- macOS Intel x64
- macOS Apple Silicon arm64

A release bundle must contain the Rails application, a compatible Ruby runtime, installed production gems, Node runtime and map-indexer dependencies, a compatible llama.cpp server runtime, precompiled Rails assets, launchers, and an empty portable storage tree.

The target computer must not need Ruby, Bundler, Node, Homebrew, WSL, Python, CMake, Git, or llama.cpp installed.

Mutable state always belongs under the bundle's storage directory: models, maps, database, settings, logs, backups and temporary files. Moving the whole bundle to a different mount point or Windows drive letter must not invalidate stored paths.

Release builds must be produced natively for their target OS/architecture. Phase 6 validates the resulting archives on clean machines before release.
