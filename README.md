<img width="300" height="" alt="Asset 1" src="https://github.com/user-attachments/assets/686d92c8-d81b-4cce-b46b-acecb24cbed9" />

A universal file converter that handles **100+ formats** across images, video, audio, 3D models, archives, documents, ebooks, and data formats. Ships as both a CLI tool and a Qt6 GUI app.

Built in C++20 with FFmpeg, Assimp, libarchive, LibreOffice, Pandoc, and Calibre under the hood.

![anyfile_gui_Q91GmX8DXI](https://github.com/user-attachments/assets/c41c8b6c-a2bf-40a7-87f0-8019cab607dd)

---

## Supported Formats

| Category | Formats |
|----------|---------|
| **Images** | PNG, JPG, WebP, BMP, TIFF, GIF, HEIC, AVIF, EXR, HDR, PSD, TGA, SVG, ICO, RAW, CR2, NEF, ARW, DNG |
| **Video** | MP4, MOV, AVI, MKV, WebM, FLV, WMV, VOB, 3GP, M4V, TS |
| **Audio** | MP3, WAV, FLAC, AAC, OGG, Opus, M4A, CAF, WMA |
| **3D Models** | FBX, OBJ, GLB, GLTF, STL, DAE, PLY, 3DS |
| **Archives** | ZIP, TAR, GZ, BZ2, XZ, 7Z, RAR*, ZSTD, TGZ, TBZ2, TXZ, LZ4, LZMA |
| **Documents** | DOCX, DOC, ODT, XLSX, XLS, ODS, PPTX, PPT, ODP, PDF, TXT, RTF, HTML, MD, RST, TEX |
| **Ebooks** | EPUB, MOBI, AZW3, AZW, FB2, DJVU, LIT |
| **Data** | JSON, XML, YAML, CSV, TSV, TOML, INI, ENV |

\* RAR is read-only (extract/convert from, cannot create)

---

## Installation

### Download

Grab the latest release from the [Releases](https://github.com/Navelol/everyfile/releases) page:

- **Windows** — `Anyfile-windows-x86_64.zip` (extract and run)
- **macOS** — `Anyfile.dmg` (drag to Applications)
- **Linux** — `Anyfile-x86_64.AppImage` (chmod +x and run)

### Build from Source

#### macOS

All dependencies are managed through Homebrew. From the project root:

```bash
brew bundle
./scripts/build_macos.sh --gui
```

`brew bundle` reads the `Brewfile` and installs everything at once — cmake, Qt6, FFmpeg, and the rest. The build script configures, compiles, and runs `macdeployqt` to produce a self-contained `.app` bundle, then ad-hoc signs it so macOS doesn't reject it on launch.

To also produce a distributable DMG:

```bash
./scripts/build_macos.sh --gui --dmg
```

Output: `build/macos/bin/anyfile_gui.app` and optionally `build/macos/Anyfile.dmg`.

#### Linux

<details>
<summary><b>Ubuntu / Debian</b></summary>

```bash
sudo apt install cmake ninja-build build-essential pkg-config \
    libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev libswresample-dev \
    libassimp-dev libarchive-dev libmagic-dev \
    qt6-base-dev qt6-declarative-dev libqt6svg6-dev
```
</details>

<details>
<summary><b>Arch / CachyOS</b></summary>

```bash
sudo pacman -S --needed cmake ninja base-devel \
    ffmpeg assimp libarchive file \
    qt6-base qt6-declarative qt6-svg
```
</details>

```bash
./scripts/build_linux.sh          # CLI only
./scripts/build_linux.sh --gui    # CLI + GUI
./scripts/build_linux.sh --appimage
```

#### Windows

<details>
<summary><b>MSYS2 MinGW64</b></summary>

```bash
pacman -S --needed \
    mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-gcc \
    mingw-w64-x86_64-ffmpeg mingw-w64-x86_64-assimp \
    mingw-w64-x86_64-libarchive mingw-w64-x86_64-file \
    mingw-w64-x86_64-qt6-base mingw-w64-x86_64-qt6-declarative mingw-w64-x86_64-qt6-svg
```
</details>

```powershell
./scripts/build_windows.ps1 -Gui
```

Output for all platforms: `build/{macos,linux,windows}/bin/`

---

## CLI Usage

```bash
# Single file conversion
anyfile video.mp4 audio.mp3
anyfile photo.heic jpg
anyfile model.fbx model.glb

# Batch conversion (entire folder)
anyfile ./videos/ mp3                      # convert all to mp3
anyfile ./media/ mp4:mp3,avi:mkv           # format mapping
anyfile ./media/ mp3 ./output/ -r          # recursive + output dir

# Info
anyfile --formats                          # list all supported formats
anyfile --help
```

### Encoding Options

```bash
# Codec & quality
anyfile input.mp4 output.mkv --vcodec libx265 --crf 20
anyfile input.wav output.mp3 --abitrate 320k

# Resolution & framerate
anyfile input.mov output.mp4 --res 1920x1080 --fps 30

# Variable bitrate (2-pass)
anyfile input.mp4 output.webm --vcodec libvpx-vp9 --vbr2-target 10M --vbr2-max 15M
```

### Batch Options

| Flag | Description |
|------|-------------|
| `-r, --recursive` | Process subdirectories |
| `-f, --force` | Overwrite existing files |
| `--list` | Dry run (list what would be converted) |

---

## GUI

The Qt6 GUI provides drag-and-drop file conversion with a format browser grouped by category, batch folder mode with per-file mapping rules, an advanced encoding panel with codec presets, and real-time progress. Conversions run asynchronously and can be cancelled mid-flight.

---

## How it works

Every conversion goes through a central dispatcher that detects the input format (magic bytes first, extension as fallback), selects the right backend, checks available disk space, writes to a temp file, and renames atomically on success. Nothing touches the output path until the conversion is confirmed complete.

Converting a video or GIF to an image format extracts the full frame sequence and bundles it into a ZIP, consistent with how PDF → image exports work.

Path validation blocks access to OS-critical directories on all platforms. For server deployments there's an optional sandbox mode that restricts all I/O to a configured root directory.

---

## External Tools

Some format categories require external tools at runtime:

| Tool | Used For | Required? |
|------|----------|-----------|
| FFmpeg | Images, video, audio | Yes |
| LibreOffice | Office documents, PDF | For document conversion |
| Pandoc | Markdown, HTML, RST, TeX | For text/markup conversion |
| Calibre | Ebook formats | For ebook conversion |
| poppler-utils | PDF → image rendering | For PDF image extraction |

On Windows and macOS, these can be bundled in a `tools/` directory alongside the binary so the app is fully self-contained. On Linux, install them through your package manager.

---

## License

MIT
