#pragma once

// ── PathValidator.h ───────────────────────────────────────────────────────────
// Centralized path and option validation for all conversion jobs.
//
// Two layers of protection:
//
//   Layer 1 — Blocklist (always active):
//     Denies access to known OS-critical directories that the converter has no
//     legitimate reason to touch (C:\Windows, /proc, /etc, etc.).
//     Symlinks are resolved BEFORE checking, so a symlink pointing at
//     /etc/shadow is caught even if the symlink itself looks safe.
//
//   Layer 2 — Sandbox (optional, recommended for server / multi-user use):
//     When PathValidator::configure() is called with a sandboxRoot, every
//     input and output path must resolve to be inside that directory.
//     This is the right tool for server deployments where untrusted users
//     supply file paths; the sandbox root should be a per-session temp dir
//     that is created fresh and destroyed after each conversion.
//
// Input length limits guard against DoS via absurdly long strings and against
// integer overflow in string operations downstream. Note: C++ std::string is
// heap-allocated, so there is no classic stack-smashing / EIP-overwrite risk
// from long path strings — but length limits are still good practice.
//
// Usage:
//   // Once at startup (optional — configures sandbox mode):
//   PathValidator::configure({ .sandboxRoot = "/tmp/anyfile_work/session42" });
//
//   // Before every dispatch:
//   if (auto err = PathValidator::validateInput(job.inputPath);  !err.empty()) …
//   if (auto err = PathValidator::validateOutput(job.outputPath); !err.empty()) …
//   if (auto err = PathValidator::validateOption(codec, "video codec"); !err.empty()) …

#include <filesystem>
#include <string>
#include <optional>
#include <algorithm>
#include <cctype>

namespace fs = std::filesystem;

namespace converter {

class PathValidator {
public:
    // ── Limits ────────────────────────────────────────────────────────────────
    // Paths longer than this are rejected outright (before any filesystem call).
    static constexpr size_t MAX_PATH_LEN = 4096;

    // Subprocess option values (codec names, bitrates, resolution strings, etc.)
    // are capped here. Values this long are never legitimate.
    static constexpr size_t MAX_OPT_LEN = 64;

    // ── Configuration ─────────────────────────────────────────────────────────
    struct Config {
        // When set, every validated path must resolve to be a descendant of
        // this directory. Recommended for any hosted / remote deployment.
        std::optional<fs::path> sandboxRoot;

        // Disable blocklist enforcement. Only turn this off if you are certain
        // your deployment environment handles OS-level isolation separately.
        bool enableBlocklist = true;
    };

    static void configure(Config cfg) {
        get_config() = std::move(cfg);
    }

    // ── Path validation ───────────────────────────────────────────────────────

    // Validate a path that will be read (input file).
    // Returns empty string on success, error message on failure.
    static std::string validateInput(const fs::path& path) {
        return validate(path, /*forWrite=*/false);
    }

    // Validate a path that will be written (output file or temp file).
    // Returns empty string on success, error message on failure.
    static std::string validateOutput(const fs::path& path) {
        return validate(path, /*forWrite=*/true);
    }

    // ── Option validation ─────────────────────────────────────────────────────
    // Validates a short string passed as a subprocess argument (codec name,
    // bitrate like "320k", resolution like "1920x1080", framerate like "30").
    //
    // Allowed characters: alphanumeric, '-', '_', '.', ':', '/'
    // This covers all legitimate ffmpeg/soffice option values while rejecting
    // shell metacharacters, spaces, and other unexpected input.
    //
    // Note: on POSIX, execvp() never invokes a shell, so a space inside a codec
    // name would just be rejected by ffmpeg as an unknown codec — there is no
    // shell injection. On Windows, quoteArg() wraps each argument in quotes
    // so spaces are similarly contained. The validation here is defence-in-depth
    // and also catches obviously invalid values early with a clear error message.
    static std::string validateOption(const std::string& opt, const char* name) {
        if (opt.empty()) return "";  // empty = "use default", always fine

        if (opt.size() > MAX_OPT_LEN)
            return std::string(name) + " value exceeds maximum length ("
                 + std::to_string(MAX_OPT_LEN) + " chars)";

        for (unsigned char c : opt) {
            if (!std::isalnum(c)
                && c != '-' && c != '_' && c != '.'
                && c != ':' && c != '/' && c != '@')
            {
                return std::string(name) + " contains an invalid character: '"
                     + static_cast<char>(c) + "'";
            }
        }
        return "";
    }

private:
    static Config& get_config() {
        static Config cfg;
        return cfg;
    }

    // Core validation logic shared by validateInput / validateOutput.
    static std::string validate(const fs::path& path, bool forWrite) {
        // 1. Reject empty paths immediately.
        if (path.empty())
            return "Path must not be empty";

        // 2. Pre-canonicalisation length check.
        //    This runs before any filesystem call to guard against DoS via
        //    absurdly long strings and to avoid any integer overflow in
        //    string operations inside fs::canonical().
        const std::string rawStr = path.string();
        if (rawStr.size() > MAX_PATH_LEN)
            return "Path exceeds maximum allowed length ("
                 + std::to_string(MAX_PATH_LEN) + " chars)";

        // 3. Resolve to canonical (real) path.
        //
        //    This is the most important step: fs::canonical() follows all
        //    symlinks and collapses every ".." component, so a path like
        //    "/safe/dir/../../etc/shadow" or a symlink pointing outside the
        //    intended tree is caught here before any blocklist or sandbox
        //    check runs.
        //
        //    For output paths the file may not exist yet. We canonicalise the
        //    parent directory (which must exist) and re-attach the filename.
        std::error_code ec;
        fs::path canonical;

        if (!forWrite) {
            canonical = fs::canonical(path, ec);
            if (ec)
                return "Input path does not exist or is inaccessible: " + rawStr;
        } else {
            fs::path parent = path.parent_path();
            if (parent.empty())
                parent = fs::current_path();

            fs::path parentCanon = fs::weakly_canonical(parent, ec);
            if (ec)
                return "Output directory is inaccessible: " + parent.string();

            canonical = parentCanon / path.filename();
        }

        // 4. Post-canonicalisation length check (a deeply nested real path
        //    could theoretically be longer than the input string).
        const std::string canonStr = canonical.string();
        if (canonStr.size() > MAX_PATH_LEN)
            return "Resolved path exceeds maximum allowed length";

        // 5. Sandbox check.
        const Config& cfg = get_config();
        if (cfg.sandboxRoot.has_value()) {
            std::error_code ec2;
            fs::path sandboxCanon = fs::weakly_canonical(*cfg.sandboxRoot, ec2);
            if (!ec2) {
                // The canonical path must start with every component of the
                // sandbox root. std::mismatch is the standard-library-safe way
                // to do a prefix check on path iterators.
                auto [rootTail, _] = std::mismatch(
                    sandboxCanon.begin(), sandboxCanon.end(),
                    canonical.begin(),   canonical.end()
                );
                if (rootTail != sandboxCanon.end())
                    return "Path is outside the allowed working directory: " + canonStr;
            }
        }

        // 6. Blocklist check.
        if (cfg.enableBlocklist) {
            if (auto err = checkBlocklist(canonical); !err.empty())
                return err;
        }

        return "";
    }

    /// Returns an error string if @p canonical falls inside a protected OS
    /// directory; returns an empty string if the path is permitted.
    ///
    /// The list is platform-specific:
    ///   - Windows  : system32, Program Files, ProgramData, and (outside
    ///                sandbox mode) the entire C:\\Users tree.
    ///   - macOS    : SIP-protected /System, /Library system subdirs,
    ///                /private/etc, /private/var/db, and standard tool dirs.
    ///   - Linux    : /etc, /proc, /sys, /dev, /boot, and standard tool dirs.
    ///
    /// Home-directory blocking is intentionally skipped in sandbox mode on
    /// every platform: the sandbox boundary already restricts access, and a
    /// sandbox root that legitimately lives under a user profile must not be
    /// blocked by this check.
    [[nodiscard]] static std::string checkBlocklist(const fs::path& canonical) {
#ifdef _WIN32
        // Normalise to lowercase with forward slashes for uniform prefix matching.
        std::string p;
        p.reserve(canonical.string().size());
        for (unsigned char c : canonical.string())
            p += static_cast<char>(std::tolower(c));
        std::replace(p.begin(), p.end(), '\\', '/');

        // Block UNC paths (\\server\share → //server/share after normalisation).
        // File conversion has no business touching network shares.
        if (p.starts_with("//"))
            return "Access to UNC network paths is not permitted: "
                 + canonical.string();

        // Extract the path component after the drive root (e.g. "c:/windows/…"
        // → "/windows/…") so that the same blocked-directory names apply
        // regardless of which drive letter Windows is installed on.
        bool hasDrive = (p.size() >= 3
                      && std::isalpha(static_cast<unsigned char>(p[0]))
                      && p[1] == ':' && p[2] == '/');
        const std::string pathAfterDrive = hasDrive ? p.substr(2) : p;

        // These directories contain OS binaries, system config, and other
        // files that file-conversion software has no business touching.
        // Checked against pathAfterDrive so they match on any drive letter.
        static const char* const BLOCKED[] = {
            "/windows",
            "/program files",
            "/program files (x86)",
            "/programdata",
            nullptr
        };
        for (int i = 0; BLOCKED[i]; ++i) {
            std::string b = BLOCKED[i];
            if (pathAfterDrive == b || pathAfterDrive.starts_with(b + '/'))
                return "Access to system directory is not permitted: "
                     + canonical.string();
        }

        // User-profile directories (X:\Users\…) are only blocked in desktop
        // mode (no sandbox). In sandbox mode the sandbox check above already
        // restricts access; blocking X:\Users here would prevent a sandbox
        // that legitimately lives under a user profile from working.
        // USERPROFILE is checked to allow the current user's own home tree.
        if (!get_config().sandboxRoot.has_value()) {
            if (hasDrive && pathAfterDrive.starts_with("/users/")) {
                const char* userProfileRaw = std::getenv("USERPROFILE");
                std::string ownHome;
                if (userProfileRaw) {
                    for (unsigned char c : std::string(userProfileRaw))
                        ownHome += static_cast<char>(std::tolower(c));
                    std::replace(ownHome.begin(), ownHome.end(), '\\', '/');
                }
                bool isOwnHome = !ownHome.empty() &&
                                 (p == ownHome || p.starts_with(ownHome + '/'));
                if (!isOwnHome)
                    return "Access to other users' home directories is not permitted: "
                         + canonical.string();
            }
        }

#elif defined(__APPLE__)
        const std::string& p = canonical.string();

        // macOS system directories protected by SIP (System Integrity Protection)
        // or that contain critical OS state.  A file converter has no legitimate
        // reason to read or write any of these.
        //
        // Note: on macOS /etc, /tmp, and /var are symlinks into /private/.
        // fs::canonical() resolves them, so we block the real /private/... paths.
        static const char* const BLOCKED[] = {
            "/System",              // SIP-protected OS core — never writable
            "/Library/Preferences", // System-wide preference plists
            "/Library/Application Support/com.apple", // Apple system support
            "/Library/LaunchDaemons",  // Root-level persistent daemons
            "/Library/LaunchAgents",   // Per-user persistent agents
            "/Library/StartupItems",   // Legacy startup items
            "/private/etc",         // Real /etc (symlink target)
            "/private/var/db",      // System databases (kext cache, etc.)
            "/private/var/run",     // Runtime state (PID files, sockets)
            "/usr/bin",
            "/usr/sbin",
            "/usr/lib",
            "/usr/libexec",
            "/bin",
            "/sbin",
            nullptr
        };
        for (int i = 0; BLOCKED[i]; ++i) {
            std::string b = BLOCKED[i];
            if (p == b || p.starts_with(b + '/'))
                return "Access to system directory is not permitted: "
                     + canonical.string();
        }

        // Block access to OTHER users' home directories.  The current user's
        // own home directory (/Users/<me>/...) must remain accessible — it is
        // where Downloads, Desktop, Documents, and all normal work files live.
        // In sandbox mode the sandbox root is the effective boundary anyway.
        if (!get_config().sandboxRoot.has_value()) {
            if (p.starts_with("/Users/")) {
                const char* home = std::getenv("HOME");
                std::string ownHome = home ? std::string(home) : "";
                // Allow anything inside the current user's own home tree.
                bool isOwnHome = !ownHome.empty() &&
                                 (p == ownHome || p.starts_with(ownHome + '/'));
                if (!isOwnHome)
                    return "Access to other users' home directories is not permitted: "
                         + canonical.string();
            }
        }

#else  // Linux
        const std::string& p = canonical.string();

        // Core OS directories that should never be read or written by a
        // file converter.
        static const char* const BLOCKED[] = {
            "/etc",
            "/proc",
            "/sys",
            "/dev",
            "/boot",
            "/root",
            "/run",
            "/var/log",
            "/var/run",
            "/usr/bin",
            "/usr/sbin",
            "/usr/lib",
            "/bin",
            "/sbin",
            "/lib",
            "/lib64",
            nullptr
        };
        for (int i = 0; BLOCKED[i]; ++i) {
            std::string b = BLOCKED[i];
            if (p == b || p.starts_with(b + '/'))
                return "Access to system directory is not permitted: "
                     + canonical.string();
        }

        // Block access to OTHER users' home directories, but allow the current
        // user's own home tree so they can convert files in ~/Downloads etc.
        if (!get_config().sandboxRoot.has_value()) {
            if (p.starts_with("/home/") || p == "/root" || p.starts_with("/root/")) {
                const char* home = std::getenv("HOME");
                std::string ownHome = home ? std::string(home) : "";
                bool isOwnHome = !ownHome.empty() &&
                                 (p == ownHome || p.starts_with(ownHome + '/'));
                if (!isOwnHome)
                    return "Access to other users' home directories is not permitted: "
                         + canonical.string();
            }
        }
#endif
        return "";
    }
};

} // namespace converter
