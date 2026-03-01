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
};

} // namespace converter
