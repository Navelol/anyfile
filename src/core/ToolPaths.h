#pragma once

// ── ToolPaths.h ───────────────────────────────────────────────────────────────
// Prepends bundled (or Homebrew-installed) tool directories to the process
// PATH so that subprocess calls (ffmpeg, soffice, pandoc, etc.) resolve to
// the right binaries without requiring them to be on the user's PATH already.
//
// Supported platforms
// ───────────────────
// Windows  — discovers tools relative to the running .exe using
//            GetModuleFileNameA().  Expected layout next to the executable:
//              tools/ffmpeg/bin/          (ffmpeg.exe, ffprobe.exe)
//              tools/pandoc/              (pandoc.exe)
//              tools/poppler/bin/         (pdftoppm.exe + DLLs)
//              tools/calibre/             (ebook-convert.exe)
//              tools/libreoffice/program/ (soffice.exe)
//
// macOS    — discovers tools in two stages:
//   Stage 1 (app bundle / portable install): looks for a tools/ directory
//            next to the running binary using _NSGetExecutablePath().
//            Inside an .app bundle the binary lives at
//            Anyfile.app/Contents/MacOS/anyfile, so the tools directory would
//            be at Anyfile.app/Contents/MacOS/tools/ — same relative layout
//            as Windows.
//   Stage 2 (Homebrew fallback): if no bundled tools/ directory is found,
//            checks the Homebrew prefix (/opt/homebrew on Apple Silicon,
//            /usr/local on Intel) so that a developer build works without
//            bundling anything.
//
// Linux    — no-op; system package manager handles tool availability.
//
// Usage
// ─────
// Call ToolPaths::init() once at the very top of main(), before any
// conversion is dispatched, so every subprocess call that follows inherits
// the updated PATH.

#ifdef _WIN32
// ── Windows ──────────────────────────────────────────────────────────────────
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#  include <string>
#  include <vector>
#  include <filesystem>

namespace converter {

/// Prepends bundled tool directories to the process PATH on Windows.
class ToolPaths {
public:
    /// Locates the tools/ directory next to the running executable and
    /// prepends each existing tool subdirectory to the process PATH.
    /// Safe to call more than once (subsequent calls are still correct,
    /// though the PATH will accumulate duplicate entries).
    static void init() {
        char buf[MAX_PATH];
        DWORD len = GetModuleFileNameA(nullptr, buf, MAX_PATH);
        if (len == 0 || len == MAX_PATH) return;

        namespace fs = std::filesystem;
        const fs::path toolsDir = fs::path(buf).parent_path() / "tools";
        if (!fs::exists(toolsDir)) return;

        // Subdirectories to prepend, in priority order.
        const std::vector<fs::path> candidates = {
            toolsDir / "ffmpeg"      / "bin",
            toolsDir / "pandoc",
            toolsDir / "poppler"     / "bin",
            toolsDir / "calibre",
            toolsDir / "libreoffice" / "program",
        };

        // Build a semicolon-separated prefix from directories that exist.
        std::string prefix;
        for (const auto& d : candidates) {
            if (fs::exists(d)) {
                if (!prefix.empty()) prefix += ';';
                prefix += d.string();
            }
        }
        if (prefix.empty()) return;

        // Prepend to the inherited PATH.
        char existingPath[32767] = {};
        GetEnvironmentVariableA("PATH", existingPath, sizeof(existingPath));

        std::string newPath = prefix;
        if (existingPath[0]) { newPath += ';'; newPath += existingPath; }
        SetEnvironmentVariableA("PATH", newPath.c_str());
    }
};

} // namespace converter

#elif defined(__APPLE__)
// ── macOS ─────────────────────────────────────────────────────────────────────
#  include <mach-o/dyld.h>  // _NSGetExecutablePath
#  include <climits>        // PATH_MAX
#  include <cstdlib>        // getenv, setenv
#  include <string>
#  include <vector>
#  include <filesystem>

namespace converter {

/// Prepends tool directories to the process PATH on macOS.
///
/// Discovery order (first match wins):
///   1. tools/ directory next to the running binary (portable / app bundle).
///   2. Homebrew prefix /opt/homebrew/bin (Apple Silicon).
///   3. Homebrew prefix /usr/local/bin (Intel Mac).
///
/// This means a bundled release finds its own tools first, while a developer
/// clone that installed dependencies via `brew install` falls through to the
/// Homebrew bin directory automatically.
class ToolPaths {
public:
    /// Resolves and prepends tool directories to the current process PATH.
    static void init() {
        namespace fs = std::filesystem;

        // ── Stage 1: look for a bundled tools/ directory ──────────────────
        // _NSGetExecutablePath returns the real path to the running binary,
        // including inside .app bundles (e.g. Anyfile.app/Contents/MacOS/anyfile).
        char rawPath[PATH_MAX];
        uint32_t size = sizeof(rawPath);
        if (_NSGetExecutablePath(rawPath, &size) == 0) {
            std::error_code ec;
            const fs::path exeDir = fs::canonical(rawPath, ec).parent_path();
            if (!ec) {
                const fs::path toolsDir = exeDir / "tools";
                if (fs::exists(toolsDir)) {
                    prependBundledTools(toolsDir);
                    return;  // bundled tools found; no need for Homebrew fallback
                }
            }
        }

        // ── Stage 2: Homebrew fallback for developer builds ───────────────
        // Try the Apple Silicon prefix first, then the Intel prefix.
        // We only prepend directories that actually exist so that the PATH
        // stays clean on non-Homebrew setups.
        static const char* const HOMEBREW_BINS[] = {
            "/opt/homebrew/bin",  // Apple Silicon (M1/M2/M3/M4)
            "/usr/local/bin",     // Intel Mac
            nullptr
        };
        std::string prefix;
        for (int i = 0; HOMEBREW_BINS[i]; ++i) {
            if (fs::exists(HOMEBREW_BINS[i])) {
                if (!prefix.empty()) prefix += ':';
                prefix += HOMEBREW_BINS[i];
            }
        }
        if (!prefix.empty()) {
            prependToPath(prefix);
        }
    }

private:
    /// Prepends each existing tool subdirectory inside @p toolsDir to PATH.
    /// The layout mirrors the Windows tools/ structure but uses POSIX
    /// conventions (colon separator, no .exe suffixes).
    static void prependBundledTools(const std::filesystem::path& toolsDir) {
        namespace fs = std::filesystem;

        // Subdirectories to prepend, in priority order.
        const std::vector<fs::path> candidates = {
            toolsDir / "ffmpeg"      / "bin",
            toolsDir / "pandoc",
            toolsDir / "poppler"     / "bin",
            toolsDir / "calibre",
            toolsDir / "libreoffice" / "MacOS",  // LibreOffice .app on macOS
        };

        std::string prefix;
        for (const auto& d : candidates) {
            if (fs::exists(d)) {
                if (!prefix.empty()) prefix += ':';
                prefix += d.string();
            }
        }
        if (!prefix.empty()) {
            prependToPath(prefix);
        }
    }

    /// Prepends @p prefix (one or more colon-separated directories) to the
    /// current process PATH environment variable.
    static void prependToPath(const std::string& prefix) {
        const char* existing = std::getenv("PATH");
        std::string newPath = prefix;
        if (existing && existing[0]) {
            newPath += ':';
            newPath += existing;
        }
        // setenv with overwrite=1 replaces the variable in the current process.
        ::setenv("PATH", newPath.c_str(), /*overwrite=*/1);
    }
};

} // namespace converter

#else
// ── Linux ─────────────────────────────────────────────────────────────────────
// No-op: the system package manager (apt, pacman, dnf, etc.) installs tools
// to standard locations already on PATH.  Nothing to do at runtime.

namespace converter {

/// No-op on Linux — tool discovery is handled by the system package manager.
class ToolPaths {
public:
    static void init() {}
};

} // namespace converter

#endif
