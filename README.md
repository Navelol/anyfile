# Anyfile

A universal file converter that handles **100+ formats** across images, video, audio, 3D models, archives, documents, ebooks, and data formats. Ships as both a CLI tool and a Qt6 GUI app.

Built in C++20 with FFmpeg, Assimp, libarchive, LibreOffice, Pandoc, and Calibre under the hood.

![anyfile_gui_Q91GmX8DXI](https://github.com/user-attachments/assets/c41c8b6c-a2bf-40a7-87f0-8019cab607dd)

---

## Supported Formats

| Category | Formats |
|----------|---------|
| **Images** | PNG, JPG, WebP, BMP, TIFF, GIF, HEIC, AVIF, EXR, HDR, PSD, TGA, SVG, ICO, RAW, CR2, NEF, ARW, DNG |
| **Video** | MP4, MOV, AVI, MKV, WebM, FLV, WMV, VOB, 3GP, M4V |
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
- **Linux** — `Anyfile-x86_64.AppImage` (chmod +x and run)

### Build from Source

#### Dependencies

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

<details>
<summary><b>Windows (MSYS2 MinGW64)</b></summary>

```bash
pacman -S --needed \
    mingw-w64-x86_64-cmake mingw-w64-x86_64-ninja mingw-w64-x86_64-gcc \
    mingw-w64-x86_64-ffmpeg mingw-w64-x86_64-assimp \
    mingw-w64-x86_64-libarchive mingw-w64-x86_64-file \
    mingw-w64-x86_64-qt6-base mingw-w64-x86_64-qt6-declarative mingw-w64-x86_64-qt6-svg
```
</details>

#### Build Commands

```bash
# Linux — CLI only
./scripts/build_linux.sh

# Linux — CLI + GUI
./scripts/build_linux.sh --gui

# Linux — Build AppImage
./scripts/build_linux.sh --appimage

# Windows
powershell scripts/build_windows.ps1 -Gui
```

Output: `build/{linux,windows}/bin/`

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

Control video/audio encoding when converting media:

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

The Qt6 GUI provides drag-and-drop file conversion with:

- **Format browser** grouped by category with search/filter
- **Batch folder mode** with per-file format mapping rules
- **Advanced encoding panel** with codec presets (H.264, H.265, VP9, AV1, etc.)
- **Real-time progress** with file size and timing info
- Async, cancellable conversions

---

## Architecture

```
src/
├── core/                    ← shared conversion library
│   ├── FormatRegistry.h     ← format detection (magic bytes + libmagic + extension)
│   ├── Dispatcher.h         ← routes jobs, atomic writes, disk space checks
│   ├── MediaConverter.h     ← FFmpeg (images, video, audio)
│   ├── ModelConverter.h     ← Assimp (3D models)
│   ├── DataConverter.h      ← JSON pivot (JSON, XML, YAML, CSV, TOML, INI, ENV)
│   ├── ArchiveConverter.h   ← libarchive (extract + repack)
│   ├── DocumentConverter.h  ← LibreOffice + Pandoc + Calibre
│   └── PdfRenderer.h        ← PDF → images via poppler
├── cli/                     ← terminal interface
└── gui/                     ← Qt6 QML interface
```

All conversions are **atomic** — output goes to a temp file first, renamed on success, cleaned up on failure. Disk space is checked before conversion begins.

---

## External Tools

Some format categories require external tools at runtime:

| Tool | Used For | Required? |
|------|----------|-----------|
| FFmpeg | Images, video, audio | Yes (core) |
| LibreOffice | Office documents, PDF | For document conversion |
| Pandoc | Markdown, HTML, RST, TeX | For text/markup conversion |
| Calibre | Ebook formats | For ebook conversion |
| poppler-utils | PDF → image rendering | For PDF image extraction |

On Windows, these can be bundled in a `tools/` directory alongside the binary. On Linux, install them from your package manager.

---

## License

MIT
