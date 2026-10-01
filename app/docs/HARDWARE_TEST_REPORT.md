# Ember Vault 2 hardware validation report

Fill this out from the generated portable archives. Do not mark a row PASS until it was exercised on that target.

| Target | Clean launch | Offline AI | Offline map | Move USB/path | Reboot | CPU-only | GPU | Result |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Windows x64 | | | | | | | | PENDING |
| Linux x64 | | | | | | | | PENDING |
| macOS Intel | | | | | | | | PENDING |
| macOS Apple Silicon | | | | | | | | PENDING |

## Additional hardware coverage

| GPU/backend | Machine | Result | Notes |
| --- | --- | --- | --- |
| NVIDIA | | PENDING | |
| AMD | | PENDING | |
| Intel | | PENDING | |
| CPU only | | PENDING | |

## Failure tests

Record results for interrupted model download, corrupt model checksum, interrupted/corrupt map copy, model replacement, copied map-pack discovery, no-network restart, and a changed Windows drive letter or Unix mount path.

When every required target is green, this report is the evidence for the Ember Vault 2.0 release sign-off.
