#pragma once

#include <string>
#include <vector>
#include <filesystem>
#include <functional>
#include <optional>
#include <atomic>
#include <random>
#include <cstdio>
#ifndef _WIN32
#  include <cstdlib>   // mkdtemp (POSIX)
#  include <unistd.h>  // mkdtemp fallback
#endif

namespace converter {

namespace fs = std::filesystem;

// ── Secure temp path generation ──────────────────────────────────────────────
// Uses std::random_device instead of predictable timestamps to prevent
// symlink attacks on shared machines.
inline fs::path makeTempName(const std::string& prefix, const std::string& suffix = "") {
    std::random_device rd;
    std::mt19937 gen(rd());
    std::uniform_int_distribution<uint32_t> dist(0, 0xFFFFFFFF);
    char hex[16];
    std::snprintf(hex, sizeof(hex), "%08x", dist(gen));
    return fs::temp_directory_path() / (prefix + hex + suffix);
}

/// Creates a temporary directory atomically. Uses mkdtemp() on POSIX to
/// prevent TOCTOU races where another process could claim the path between
/// name generation and directory creation.
inline fs::path makeTempDir(const std::string& prefix) {
#ifdef _WIN32
    // Windows: no mkdtemp; fall back to random name + create_directories
    auto p = makeTempName(prefix);
    fs::create_directories(p);
    return p;
#else
    std::string tmpl = (fs::temp_directory_path() / (prefix + "XXXXXXXX")).string();
    char* result = mkdtemp(tmpl.data());
    if (!result) {
        // Fallback if mkdtemp fails (shouldn't happen with valid /tmp)
        auto p = makeTempName(prefix);
        fs::create_directories(p);
        return p;
    }
    return fs::path(result);
#endif
}

// ── Format categories ─────────────────────────────────────────────────────────
enum class Category {
    Image,
    Video,
    Audio,
    Model3D,
    Document,
    Ebook,
    Archive,
    Data,
    Unknown,
};

// ── A detected file format ────────────────────────────────────────────────────
struct Format {
    std::string ext;
    Category    category;
    std::string mimeType;
};

// ── Progress callback — 0.0 to 1.0 ───────────────────────────────────────────
using ProgressFn = std::function<void(float progress, const std::string& message)>;

// ── The result of a conversion ────────────────────────────────────────────────
struct ConversionResult {
    bool        success   = false;
    std::string errorMsg;
    fs::path    outputPath;

    std::vector<std::string> warnings;

    double durationSeconds = 0.0;
    size_t inputBytes      = 0;
    size_t outputBytes     = 0;

    static ConversionResult ok(fs::path out, double secs = 0.0) {
        return { true, "", std::move(out), {}, secs };
    }

    static ConversionResult err(std::string msg) {
        return { false, std::move(msg) };
    }

    static ConversionResult cancelled() {
        return { false, "Conversion cancelled" };
    }
};

// ── A conversion job ──────────────────────────────────────────────────────────
struct ConversionJob {
    fs::path    inputPath;
    fs::path    outputPath;
    Format      inputFormat;
    Format      outputFormat;
    ProgressFn  onProgress;     // optional, can be nullptr

    // Set to true from any thread to request cancellation.
    // Converters check this periodically and return ConversionResult::cancelled().
    // The caller owns the atomic and must ensure it outlives the conversion.
    std::atomic<bool>* cancelFlag = nullptr;

    // ── Optional media encoding overrides ─────────────────────────────────
    std::optional<std::string> videoCodec;
    std::optional<std::string> audioCodec;
    std::optional<std::string> videoBitrate;
    std::optional<std::string> videoMaxRate;  // VBR max bitrate cap (e.g. "12M")
    std::optional<std::string> audioBitrate;
    bool twoPass = false;  // true = VBR 2-pass encode
    std::optional<std::string> resolution;
    std::optional<std::string> framerate;
    std::optional<int>         crf;
    std::optional<std::string> pixelFormat;
    bool force = false;
};

} // namespace converter