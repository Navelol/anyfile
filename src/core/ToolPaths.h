#pragma once

// ── ToolPaths.h ───────────────────────────────────────────────────────────────
// On Windows, prepends bundled tool directories to the process PATH so that
// subprocess calls (ffmpeg, soffice, pandoc, etc.) resolve to the bundled
// copies rather than requiring them to be installed system-wide.
//
// Expected layout next to the executable:
//   tools/ffmpeg/bin/          ffmpeg.exe ffprobe.exe
//   tools/pandoc/              pandoc.exe
//   tools/poppler/bin/         pdftoppm.exe + DLLs
//   tools/calibre/             ebook-convert.exe
//   tools/libreoffice/program/ soffice.exe
//
// Call ToolPaths::init() once at the top of main() before any conversions.

#ifdef _WIN32
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <string>
#  include <vector>
#  include <filesystem>

namespace converter {

class ToolPaths {
public:
    static void init() {
        // Find directory containing the running executable
        char buf[MAX_PATH];
        DWORD len = GetModuleFileNameA(nullptr, buf, MAX_PATH);
        if (len == 0 || len == MAX_PATH) return;

        namespace fs = std::filesystem;
        fs::path exeDir = fs::path(buf).parent_path();
        fs::path toolsDir = exeDir / "tools";

        if (!fs::exists(toolsDir)) return;

        // Subdirectories to prepend, in priority order
        const std::vector<fs::path> toolDirs = {
            toolsDir / "ffmpeg"      / "bin",
            toolsDir / "pandoc",
            toolsDir / "poppler"     / "bin",
            toolsDir / "calibre",
            toolsDir / "libreoffice" / "program",
        };

        // Build prefix string from dirs that actually exist
        std::string prefix;
        for (auto& d : toolDirs) {
            if (fs::exists(d)) {
                if (!prefix.empty()) prefix += ';';
                prefix += d.string();
            }
        }

        if (prefix.empty()) return;

        // Prepend to existing PATH
        char existingPath[32767] = {};
        GetEnvironmentVariableA("PATH", existingPath, sizeof(existingPath));

        std::string newPath = prefix;
        if (existingPath[0]) { newPath += ';'; newPath += existingPath; }

        SetEnvironmentVariableA("PATH", newPath.c_str());
    }
};

} // namespace converter

#else

// No-op on Linux — system package manager handles tool availability
namespace converter {
class ToolPaths {
public:
    static void init() {}
};
} // namespace converter

#endif
