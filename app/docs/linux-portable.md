# Linux x64 portable release

Use an **ext4 USB filesystem**, mounted with execution allowed (`exec`, not
`noexec`), owned/writable by the user who launches Ember Vault. Extract the
`.tar.gz` directly onto it; tar preserves executable modes and symlinks.
FAT32 and exFAT direct execution are not supported or validated. FAT32 also
cannot hold a file larger than 4 GiB. Changing modes with chmod does not fix
FAT permission semantics. An ext4 filesystem mounted `noexec` also will not work.

```sh
sha256sum -c ember-vault-linux-x64.tar.gz.sha256
mkdir -p /media/$USER/EMBER
# Replace this mount path with your already-mounted ext4 USB drive.
tar -xzf ember-vault-linux-x64.tar.gz -C /media/$USER/EMBER
/media/$USER/EMBER/ember-vault-linux-x64/portable/start-linux.sh
```

Timezone data is bundled too. Bundled mode starts Puma directly to keep
Rails server temporary directories out of the application tree.

The launcher writes databases, models, maps, settings, logs, backups, temporary
files and the persistent `.secret_key_base` under `storage`. It prepares the
database on first launch. `storage/ember-vault.url` records the actual healthy
web server URL; the browser opens that URL even if port 3000 is occupied.
Use `portable/start-linux.sh stop` to stop the web server. Quit AI through the
app before safely ejecting the drive. Do not eject while processes use storage.
`EMBER_VAULT_NO_BROWSER=1` suppresses opening the browser.

Runtime components are Ruby 3.3.8, Node 22.22.0 and llama.cpp v0.4.1, commit
`b29c606e28a01b1bc8c1351026a0fa6e616bf6c4`. Bundled mode requires bundled
executables and never substitutes host Ruby, Node or llama-server. Launching
requires no downloads, compilation, sudo or package installation. Ordinary
Linux facilities (glibc, shell/core utilities and GPU drivers) remain
OS responsibilities. A browser and xdg-open are optional for automated opening.
The Vulkan loader is bundled. Acceleration requires a compatible driver and GPU; CPU
mode is available with `EMBER_VAULT_GPU_LAYERS=0`. Automatic GPU startup failure
retries CPU mode. The conservative CPU build requires SSE4.2; AVX, AVX2, FMA,
F16C and BMI2 are disabled. This is not support for every historical x86-64 CPU.

## Building and validating

Build Ruby and native gems on Ubuntu 22.04/glibc 2.35 or an equivalent baseline,
not on the newer development host. Stage complete runtimes at
`portable/runtime/linux-x64/{ruby,node,llama}`. Ruby's production bundle uses
`ruby/lib/ruby/gems/3.3.0` as BUNDLE_PATH, with development/test groups excluded.
Do not copy fragments from host Ruby or `/usr/bin/node`.

Ruby source archive SHA256:
`5ae28a87a59a3e4ad66bc2931d232dbab953d0aa8f6baf3bc4f8f80977c89cab`.
Configure Ruby with `--prefix=/runtime/ruby --enable-load-relative --disable-install-doc --disable-yjit`
and `CFLAGS='-O2 -ffile-prefix-map=/build=.'`, then build/install Ruby and install
the locked production bundle. Node uses the complete official v22.22.0 Linux
x64 tarball, plus baseline libstdc++/libgcc in `node/lib` and a relative
`$ORIGIN/../lib` RPATH on its executable. Build llama from the exact commit above, with these options:

```sh
cmake -S llama.cpp -B build -DCMAKE_BUILD_TYPE=Release \
  -DGGML_VULKAN=ON -DGGML_NATIVE=OFF -DGGML_SSE42=ON \
  -DGGML_AVX=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF \
  -DGGML_F16C=OFF -DGGML_BMI2=OFF \
  -DGGML_BUILD_TESTS=OFF -DGGML_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_IS_DEV=OFF -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  '-DCMAKE_BUILD_RPATH=$ORIGIN;$ORIGIN/../lib'
cmake --build build --target llama-server --parallel 3
```

Verify generated compile commands, not just CMake option values. Copy the server
and all its llama/ggml shared libraries to `llama/llama-server` and `llama/lib`.
Bundle non-glibc runtime dependencies from the compatibility baseline, including
OpenSSL, YAML, readline/tinfo, libffi, GMP/crypt, libstdc++, libgcc and OpenMP.
Bundle the Vulkan loader too; leave glibc and GPU drivers to the target OS. Inspect every ELF
with readelf/ldd. Use patchelf to set each dynamic ELF RPATH to the relative bundled library directory (for example `$ORIGIN/lib` for the llama payload and `$ORIGIN` for llama shared libraries). Remove build-tree RPATHs and debug data; do not embed developer
home paths. Keep libstdc++ and libgcc in `runtime/llama/compat`, outside the normal library
search path. The packaged llama wrapper first probes the payload using system
C++ support libraries, then adds bundled compatibility libraries if needed.
This prevents older bundled C++ libraries from blocking newer system GPU
drivers. Ruby does not require those C++ libraries. The development build used Ubuntu 22.04 GCC 11.4 and a newer glslc
2023.8 shader compiler at build time; that compiler is not a release dependency.

```sh
ruby test/runtime_paths_test.rb
# Optional local offline content: only models/ and maps/ are copied.
EMBER_VAULT_CONTENT_DIR=portable/data/release-content \
  ruby script/build_portable.rb linux-x64
# The build script precompiles assets with bundled Ruby and a dummy secret.
ruby script/validate_portable.rb dist/ember-vault-linux-x64
# Archive only clean storage/content; exclude smoke-test databases and secrets.
tar -czf dist/ember-vault-linux-x64.tar.gz -C dist ember-vault-linux-x64
(cd dist && sha256sum ember-vault-linux-x64.tar.gz > ember-vault-linux-x64.tar.gz.sha256)
# Extract into a fresh directory before the final smoke test.
python3 script/smoke_portable.py /path/to/extracted/ember-vault-linux-x64 /path/to/existing-small.gguf
```

The smoke test uses temporary fresh storage and a PATH containing only selected
shell utilities. It checks Rails/SQLite, map indexing from a tiny valid PMTiles
fixture, the occupied-port case, browser URL, health, CPU inference with Vulkan
discovery disabled and GPU inference with actual offloading. Run a further
CPU/web smoke in a clean baseline root without installed Ruby or Node.
Generated runtimes, offline content, databases, secrets and dist archives stay
outside Git. `BUILD_MANIFEST.json` records packaged versions and build details.

## Included offline content

This release includes the existing SurvivalAI Qwen 0.5B GGUF and Arkansas
PMTiles pack. Other model/region downloads are optional and require network
access only when requested. The shipped storage contains no pre-existing
databases, user settings, caches or Rails secret.
