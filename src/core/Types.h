#pragma once

#include <string>
#include <vector>
#include <filesystem>
#include <functional>
#include <optional>

namespace converter {

namespace fs = std::filesystem;

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
    std::string ext;        // lowercase, no dot — "mp4", "fbx", "png"
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

    // Warnings that didn't fail the conversion but are worth surfacing
    std::vector<std::string> warnings;

    // Stats
    double durationSeconds = 0.0;
    size_t inputBytes      = 0;
    size_t outputBytes     = 0;

    static ConversionResult ok(fs::path out, double secs = 0.0) {
        return { true, "", std::move(out), {}, secs };
    }

    static ConversionResult err(std::string msg) {
        return { false, std::move(msg) };
    }
};

// ── A conversion job ──────────────────────────────────────────────────────────
struct ConversionJob {
    fs::path    inputPath;
    fs::path    outputPath;
    Format      inputFormat;
    Format      outputFormat;
    ProgressFn  onProgress;  // optional, can be nullptr

    // ── Optional media encoding overrides ─────────────────────────────────
    // If unset, MediaConverter will apply sensible defaults per output format.
    std::optional<std::string> videoCodec;    // e.g. "libx264", "libx265", "vp9"
    std::optional<std::string> audioCodec;    // e.g. "aac", "libmp3lame", "libopus"
    std::optional<std::string> videoBitrate;  // e.g. "2M", "500k"
    std::optional<std::string> audioBitrate;  // e.g. "192k", "320k"
    std::optional<std::string> resolution;    // e.g. "1920x1080", "1280x720"
    std::optional<std::string> framerate;     // e.g. "30", "60", "24"
    std::optional<int>         crf;           // e.g. 18 (lossless-ish) to 51 (terrible)
    std::optional<std::string> pixelFormat;   // e.g. "yuv420p", "yuv444p"
    bool force = false;  // overwrite output if it already exists
};

} // namespace converter