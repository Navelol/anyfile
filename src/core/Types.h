#pragma once

#include <string>
#include <vector>
#include <filesystem>
#include <functional>
#include <optional>
#include <atomic>

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