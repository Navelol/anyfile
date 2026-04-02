# macOS Portability Report

**Branch:** `impl/macos_strapon`
**Date:** 2026-04-02
**Prepared by:** Linux build team — for review by macOS maintainer

---

## Summary

The macOS branch introduced VideoToolbox GPU acceleration and DMG packaging.
No macOS-specific C++ code was found to have correctness bugs, but there are
several items that require verification on a real macOS build and one
deliberate design gap worth noting.

---

## Items Requiring macOS Verification

### 1. `Dispatcher.h` — `ftruncate` after `F_PREALLOCATE` (medium risk)

**File:** `src/core/Dispatcher.h`, lines 184–194

```cpp
#elif defined(__APPLE__)
    int fd = open(path.string().c_str(), O_WRONLY | O_CREAT, 0644);
    if (fd < 0) return;
    fstore_t store = {F_ALLOCATECONTIG, F_PEOFPOSMODE, 0, static_cast<off_t>(size), 0};
    if (fcntl(fd, F_PREALLOCATE, &store) == -1) {
        store.fst_flags = F_ALLOCATEALL;  // fallback: non-contiguous
        fcntl(fd, F_PREALLOCATE, &store);
    }
    ftruncate(fd, static_cast<off_t>(size));
    close(fd);
```

`ftruncate` is called unconditionally after the fallback `F_PREALLOCATE`. If
_both_ `fcntl` calls fail (e.g., on a read-only volume or a filesystem that
doesn't support `F_PREALLOCATE` such as exFAT or network mounts), the file is
still truncated to `size` bytes of zeros, which will be immediately overwritten
by the converter — so this is harmless in practice. However, on a full volume
where `F_PREALLOCATE` fails _because_ there's not enough space, the
`ftruncate` will also fail silently and the conversion will proceed into a
file-full error later. This should be verified on a near-full APFS volume.

**Recommended fix (optional):** Check the return value of the second `fcntl`
fallback and skip `ftruncate` if allocation failed entirely.

---

### 2. `ToolPaths.h` — Bundled tools layout on macOS (low risk)

**File:** `src/core/ToolPaths.h`, lines 184–206

The macOS bundled tools path resolver looks for a `tools/` directory next to
the binary using `_NSGetExecutablePath`. Inside a `.app` bundle the binary
lives at `Anyfile.app/Contents/MacOS/anyfile`, so bundled tools must be at
`Anyfile.app/Contents/MacOS/tools/`.

**Verify that the DMG packaging script places tools at this exact path.**
If tools are placed at `Anyfile.app/Contents/Resources/tools/` (a common
convention for app resources), Stage 1 discovery will silently fall through to
the Homebrew fallback — which works for developer machines but not for
end-user DMG installs.

---

### 3. `DocumentConverter.h` — `soffice` binary name (low risk)

**File:** `src/core/DocumentConverter.h`, lines 12–18

```cpp
#elif defined(__APPLE__)
    static constexpr const char* SOFFICE_BIN = "soffice";
```

On macOS, LibreOffice installs its binary as
`/Applications/LibreOffice.app/Contents/MacOS/soffice`. `ToolPaths::init()`
adds this to `PATH` via the CASK_BINS Stage 3 discovery — but only if
LibreOffice is installed in `/Applications/`. If the user installed LibreOffice
elsewhere (e.g., `~/Applications/`), soffice won't be found.

**Verify** document conversion works on a clean macOS machine where
LibreOffice is installed in `~/Applications/` rather than `/Applications/`.

---

### 4. CI smoke test — macOS path to binary (low risk)

**File:** `.github/workflows/ci.yml`, line 102–103

```yaml
- name: GUI smoke test
  run: |
    QT_QPA_PLATFORM=offscreen ./build/macos/bin/anyfile_gui.app/Contents/MacOS/anyfile_gui --smoke-test
```

`QT_QPA_PLATFORM=offscreen` is a Linux Qt mechanism. On macOS, Qt uses the
native Cocoa platform by default; setting `QT_QPA_PLATFORM=offscreen` in CI
works for headless testing but bypasses the native window compositor entirely.
This means the smoke test verifies QML loads but does **not** verify that the
app window renders correctly via the Cocoa backend.

This is acceptable for CI but the macOS maintainer should confirm the app
renders correctly on a real display at least once per release.

---

## Changes Made on Linux/Windows That DO NOT Affect macOS

The following fixes were made to the codebase on this branch. They are
guarded by `#ifndef __APPLE__` / `#elif defined(__linux__)` / `#ifdef _WIN32`
and should have **zero impact** on macOS builds:

| File | Change | macOS impact |
|------|--------|-------------|
| `PathValidator.h` | Windows: added UNC path block + multi-drive support | None — under `#ifdef _WIN32` |
| `Dispatcher.h` | Windows: temp files no longer get a `.` prefix | None — under `#ifdef _WIN32` |
| `ConverterBridge.h` | Linux: added VA-API GPU presets alongside NVENC | None — under `#elif defined(__linux__)` |
| `Types.h` | `mkdtemp` template uses 6 X's (was 8) | Harmless — macOS libc accepts both; now POSIX-conformant |
| `ArchiveConverter.h`, `PdfRenderer.h`, `MediaConverter.h` | `static_cast<size_t>(f.gcount())` | No behavior change |

---

## No Action Required

These items were investigated and confirmed **not bugs**:

- `Subprocess.h` — macOS uses the same POSIX `fork`/`execvp` path as Linux. Correct.
- `ToolPaths.h` macOS section — `_NSGetExecutablePath` + Homebrew fallback is correct.
- `PathValidator.h` macOS blocklist — `/System`, `/Library/...`, `/private/etc` etc. are correct.
- GPU presets in `ConverterBridge.h` — VideoToolbox presets are properly gated under `#ifdef __APPLE__`.

---

## CI Fix Applied (Already Merged)

The Linux CI was fixed to install `qtsvg` alongside `qtquick3d`:

```yaml
modules: 'qtquick3d qtsvg'
```

This unblocked the Linux build. No macOS CI changes were needed.
