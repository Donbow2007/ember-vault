# Ember Vault 2 release validation

Automated release gates cover each native target: Windows x64, Linux x64, macOS Intel x64 and macOS Apple Silicon.

## Automated gates

- Bundle contains its own Ruby runtime and production gems.
- Bundle contains llama-server and required runtime libraries.
- Rails assets are precompiled.
- Map indexer dependencies are present.
- Portable storage directories exist.
- CI tests, Ruby security scan and JavaScript dependency audit pass.
- The application stores mutable state beneath portable storage rather than the source tree.

## Clean-machine acceptance

Before declaring 2.0 final, test each generated archive on a clean target without Ruby, Node, llama.cpp, Git, CMake, Homebrew or WSL installed.

For each platform:

1. Extract/copy the bundle to removable storage.
2. Launch Ember Vault.
3. Complete first-run setup.
4. Install/select a model and ask several questions.
5. Add a map pack, discover it, browse it and search it offline.
6. Disconnect networking and repeat AI/map use.
7. Stop Ember Vault, remove the drive, reconnect it at a different mount point or Windows drive letter, and launch again.
8. Confirm settings, database, models and maps survived the move.
9. Replace/remove a model and verify restart behavior.
10. Interrupt a model/map transfer and verify no corrupt final asset is treated as installed.
11. Reboot the host and launch again.
12. Exercise CPU-only mode. Record GPU tests separately for NVIDIA, AMD and Intel hardware where available.

Hardware-specific GPU coverage and physical USB removal cannot be truthfully substituted by CI; record those results in the release notes when performed.
