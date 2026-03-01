# converter

Universal file converter — CLI + GUI (coming soon).  
Written in C++20. Uses FFmpeg, Assimp, and more under the hood.

---

## Project Structure

```
converter/
├── core/               ← shared conversion logic (linked by CLI + GUI)
│   ├── Types.h         ← ConversionResult, ConversionJob, Format
│   ├── FormatRegistry.h← format detection + target mapping
│   ├── Dispatcher.h    ← routes jobs to the right converter
│   ├── MediaConverter.h← FFmpeg (images, video, audio)
│   └── ModelConverter.h← Assimp (3D formats)
├── cli/
│   └── main.cpp        ← terminal interface
├── gui/                ← Qt6 GUI (not yet implemented)
├── scripts/
│   ├── build_linux.sh
│   └── build_windows.bat
└── CMakeLists.txt
```

---

## Dependencies

### Linux (apt)
```bash
sudo apt install \
    cmake ninja-build build-essential \
    libavcodec-dev libavformat-dev libavutil-dev \
    libswscale-dev libswresample-dev \
    libassimp-dev \
    libarchive-dev
```

> For GUI support also install: `sudo apt install qt6-base-dev qt6-declarative-dev`

### Arch / CachyOS (pacman)
```bash
sudo pacman -S --needed \
    cmake ninja base-devel \
    ffmpeg \
    assimp \
    libarchive
```

> For GUI support also install: `sudo pacman -S qt6-base qt6-declarative`

### Windows (vcpkg)
```bash
vcpkg install ffmpeg assimp
```

---

## Build

### Linux
```bash
chmod +x scripts/build_linux.sh
./scripts/build_linux.sh              # CLI only (default)
./scripts/build_linux.sh --gui        # CLI + Qt6 GUI
./scripts/build_linux.sh --debug      # debug build
```

Binary is output to `build/linux/bin/anyfile`.

### Windows
```bat
scripts\build_windows.bat
```

### With GUI (Qt6 required)
```bash
./scripts/build_linux.sh --gui
# or manually:
cmake -S . -B build/linux -DBUILD_GUI=ON && cmake --build build/linux --parallel
```

---

## CLI Usage

```bash
# Convert by specifying output file
converter video.mp4 audio.mp3
converter model.fbx model.glb
converter image.png output.webp

# Convert using --to flag (output in same directory)
converter photo.heic --to jpg
converter document.wav --to flac

# List all supported formats
converter --formats

# Help
converter --help
```

---

## Adding a New Converter

1. Create `core/YourConverter.h` with a static `convert(const ConversionJob&)` method
2. Add a route in `core/Dispatcher.h` in the `route()` function
3. Register the formats and targets in `core/FormatRegistry.h`

---

## Roadmap

- [x] Project scaffold
- [x] FFmpeg media conversion (video, audio, image)
- [x] Assimp 3D conversion
- [x] CLI with progress bar
- [ ] Data format conversion (JSON ↔ XML ↔ YAML ↔ CSV)
- [ ] Archive conversion (libarchive)
- [ ] Qt6 GUI
- [ ] Batch conversion
- [ ] Drag and drop (GUI)
