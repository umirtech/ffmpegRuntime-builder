# FFShell FFmpeg Runtime Builder for Android

Build monolithic FFmpeg Android libraries (`libffmpeg.so`) with GitHub Actions.

Supported ABIs:

* `arm64-v8a`
* `armeabi-v7a`
* `x86`
* `x86_64`

The build uses Android NDK `r28c` and validates ELF type, SONAME, exported FFShell symbols, 16 KB alignment, and unwanted dependencies.

Repository:

https://github.com/umirtech/ffmpegRuntime-builder

## Fork and Enable Actions

1. Open the repository.
2. Click **Fork**.
3. Open your fork.
4. Go to **Actions**.
5. Enable GitHub Actions if prompted.

## Build with GitHub Actions

1. Open **Actions**.
2. Select **Build FFShell FFmpeg runtime for Android**.
3. Click **Run workflow**.
4. Choose a build type:

    * `Minimal`
    * `Full`

The workflow builds all supported ABIs automatically.

## Build Types

Minimal:

```bash
./android.sh --arch <architecture>
```

Full:

```bash
./android.sh --arch <architecture> --full
```

## Download Artifacts

After the workflow finishes:

1. Open the successful workflow run.
2. Scroll to **Artifacts**.
3. Download the ABI package you need.

Artifacts include:

```text
libffmpeg.so
```

and the FFShell header:

```text
include/ffshell/ffshell_ffmpeg.h
```

## Use in an Android Project

Copy the libraries into your Android project:

```text
app/src/main/jniLibs/
├── arm64-v8a/libffmpeg.so
├── armeabi-v7a/libffmpeg.so
├── x86/libffmpeg.so
└── x86_64/libffmpeg.so
```

Include the FFShell header in native code:

```cpp
#include <ffshell/ffshell_ffmpeg.h>
```

## Build Locally

Make the script executable:

```bash
chmod +x android.sh
```

Build an ABI:

```bash
./android.sh --arch armv8a
```

Full build:

```bash
./android.sh --arch armv8a --full
```

Supported architectures:

```text
armv8a
armv7a
x86
x86-64
```

## Create a Distribution ZIP

Run:

```bash
chmod +x package.sh
./package.sh
```

The package is generated under:

```text
build/package/
```

The output contains:

```text
arm64-v8a/libffmpeg.so
armeabi-v7a/libffmpeg.so
x86/libffmpeg.so
x86_64/libffmpeg.so
manifest.json
```

## Automatic Packaging

To package all ABIs with GitHub Actions:

1. Open **Actions**.
2. Select **Build FFShell Distributable Package**.
3. Click **Run workflow**.
4. Choose `Minimal` or `Full`.

The workflow creates:

```text
ffshell-ffmpeg-<version>-android.zip
```

## Create a Release

Create and push a version tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

Tags beginning with `v` trigger the packaging workflow and attach the ZIP to a GitHub Release.

## Update Your Fork

```bash
git remote add upstream https://github.com/umirtech/ffmpegRuntime-builder.git
git fetch upstream
git checkout main
git merge upstream/main
git push origin main
```

## Troubleshooting

Find the generated library:

```bash
find ffmpeg-build -name libffmpeg.so
```

Inspect dependencies:

```bash
llvm-readelf -d libffmpeg.so
```

Inspect exported symbols:

```bash
llvm-nm -D --defined-only libffmpeg.so
```

The library should export:

```text
ffshell_ffmpeg_run
ffshell_ffprobe_run
```

If 16 KB alignment or dependency validation fails, check the linker configuration and FFmpeg build options.

## License

See the repository `LICENSE` file. Verify FFmpeg and third-party codec licensing before distributing custom builds.
