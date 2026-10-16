# FFShell FFmpeg Runtime Builder for Android

Build monolithic FFmpeg Android libraries (`libffmpeg.so`) with GitHub Actions.

Supported ABIs:

* `arm64-v8a`
* `armeabi-v7a`
* `x86`
* `x86_64`

The build uses Android NDK `r27c` and validates ELF type, SONAME, exported FFShell symbols, 16 KB alignment, and unwanted dependencies.

## Fork and Enable Actions

1. Click **Fork**.
2. Open your fork.
3. Go to **Actions**.
4. Enable GitHub Actions if prompted.

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

## License

See the repository `LICENSE` file. Verify FFmpeg and third-party codec licensing before distributing custom builds.
