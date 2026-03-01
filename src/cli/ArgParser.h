#pragma once

#include <string>
#include <vector>
#include <map>
#include <optional>
#include <filesystem>
#include <iostream>
#include <sstream>

namespace fs = std::filesystem;

namespace converter {

struct ParsedArgs {
    bool isHelp    = false;
    bool isFormats = false;
    bool recursive = false;
    bool force     = false;
    bool isBatch   = false;
    bool hasError  = false;
    std::string errorMsg;

    // Single file mode
    fs::path inputPath;
    fs::path outputPath;

    // Batch mode
    fs::path inputDir;
    fs::path outputDir;
    std::string targetExt;  // e.g. "mp4" — used when no format map

    // Format mapping — "mp4:mp3||avi:mp4" → {{"mp4","mp3"},{"avi","mp4"}}
    // If empty and targetExt is set, convert everything possible to targetExt
    std::map<std::string, std::string> formatMap;

    // Media encoding overrides
    std::optional<std::string> videoCodec;
    std::optional<std::string> audioCodec;
    std::optional<std::string> videoBitrate;
    std::optional<std::string> audioBitrate;
    std::optional<std::string> resolution;
    std::optional<std::string> framerate;
    std::optional<int>         crf;
    std::optional<std::string> pixelFormat;
};

class ArgParser {
public:
    static ParsedArgs parse(int argc, char* argv[]) {
        std::vector<std::string> args(argv + 1, argv + argc);
        return parse(args);
    }

    static ParsedArgs parse(const std::vector<std::string>& args) {
        ParsedArgs result;

        if (args.empty()) return result;

        size_t i = 0;

        // ── Global flags ──────────────────────────────────────────────────────
        if (args[i] == "--help" || args[i] == "-h") { result.isHelp    = true; return result; }
        if (args[i] == "--formats")                 { result.isFormats = true; return result; }

        // ── First positional: input file or directory ─────────────────────────
        fs::path first = args[i++];

        if (fs::is_directory(first)) {
            // ── Batch mode ────────────────────────────────────────────────────
            result.isBatch  = true;
            result.inputDir = first;

            if (i >= args.size()) {
                result.hasError = true;
                result.errorMsg = "Batch mode requires a target format or format map (e.g. mp4 or mp4:mp3||avi:mp4)";
                return result;
            }

            // Second positional: format/map OR output directory
            std::string second = args[i++];

            if (isFormatArg(second)) {
                // Could be "mp4" or "mp4:mp3||avi:mp4"
                if (second.find(':') != std::string::npos) {
                    // Format map
                    auto fmtMap = parseFormatMap(second);
                    if (fmtMap.empty()) {
                        result.hasError = true;
                        result.errorMsg = "Invalid format map: '" + second + "'. Expected e.g. mp4:mp3||avi:mp4";
                        return result;
                    }
                    result.formatMap = fmtMap;
                } else {
                    result.targetExt = second;
                }

                // Optional third positional: output directory
                if (i < args.size() && !isFlag(args[i])) {
                    result.outputDir = args[i++];
                } else {
                    // Default: input_dir + "_out"
                    result.outputDir = first.string() + "_out";
                }
            } else {
                // Second arg is a path — error, format must come before output dir
                result.hasError = true;
                result.errorMsg = "Expected a format or format map after input directory, got: '" + second + "'";
                return result;
            }

        } else {
            // ── Single file mode ──────────────────────────────────────────────
            result.isBatch   = false;
            result.inputPath = first;

            if (i >= args.size()) {
                result.hasError = true;
                result.errorMsg = "Expected output file or format extension";
                return result;
            }

            std::string second = args[i++];

            if (isPureExtension(second)) {
                // e.g. "mp4" — derive output filename from input
                std::string ext = second;
                if (ext[0] == '.') ext = ext.substr(1);
                result.outputPath = first.parent_path() / (first.stem().string() + "." + ext);
            } else {
                // e.g. "output.mp4" or "./output/video.mp4"
                result.outputPath = second;
            }
        }

        // ── Remaining flags (shared by both modes) ────────────────────────────
        while (i < args.size()) {
            const std::string& arg = args[i];

            if (arg == "-r" || arg == "--recursive") { result.recursive = true; ++i; }
            else if (arg == "--f" || arg == "--force") { result.force = true; ++i; }
            else if (auto v = consumeFlag(args, i, "--video-codec"))    { result.videoCodec   = v; }
            else if (auto v = consumeFlag(args, i, "--audio-codec"))    { result.audioCodec   = v; }
            else if (auto v = consumeFlag(args, i, "--video-bitrate"))  { result.videoBitrate = v; }
            else if (auto v = consumeFlag(args, i, "--audio-bitrate"))  { result.audioBitrate = v; }
            else if (auto v = consumeFlag(args, i, "--resolution"))     { result.resolution   = v; }
            else if (auto v = consumeFlag(args, i, "--framerate"))      { result.framerate    = v; }
            else if (auto v = consumeFlag(args, i, "--pixel-format"))   { result.pixelFormat  = v; }
            else if (auto v = consumeFlag(args, i, "--crf")) {
                try { result.crf = std::stoi(*v); }
                catch (...) {
                    result.hasError = true;
                    result.errorMsg = "--crf requires an integer (e.g. 23)";
                    return result;
                }
            } else {
                // Unknown flag — warn but continue
                std::cerr << "  Warning: unknown option '" << arg << "' — ignoring\n";
                ++i;
            }
        }

        return result;
    }

private:
    // "mp4", "mp3", "glb" etc. — no slashes, no dots (or just a leading dot)
    static bool isPureExtension(const std::string& s) {
        if (s.empty()) return false;
        if (s[0] == '-') return false;  // it's a flag

        // Contains path separators → it's a path
        if (s.find('/') != std::string::npos) return false;
        if (s.find('\\') != std::string::npos) return false;

        // Contains a colon (format map) or pipe → format arg but not pure ext
        if (s.find(':') != std::string::npos) return false;

        // If it has a dot not at position 0 → it's a filename like "output.mp4"
        size_t dot = s.find('.');
        if (dot != std::string::npos && dot != 0) return false;

        return true;
    }

    // Format arg = pure extension OR format map string
    static bool isFormatArg(const std::string& s) {
        if (s.empty() || s[0] == '-') return false;
        if (s.find('/') != std::string::npos) return false;
        if (s.find('\\') != std::string::npos) return false;
        // Pure ext or format map
        return true;
    }

    static bool isFlag(const std::string& s) {
        return !s.empty() && s[0] == '-';
    }

    // Parse "mp4:mp3,avi:mp4" → {{"mp4","mp3"},{"avi","mp4"}}
    static std::map<std::string, std::string> parseFormatMap(const std::string& s) {
        std::map<std::string, std::string> result;

        // Split on ","
        std::vector<std::string> pairs;
        size_t start = 0;
        while (true) {
            size_t pos = s.find(",", start);
            if (pos == std::string::npos) {
                pairs.push_back(s.substr(start));
                break;
            }
            pairs.push_back(s.substr(start, pos - start));
            start = pos + 1;
        }

        for (auto& pair : pairs) {
            size_t colon = pair.find(':');
            if (colon == std::string::npos) return {};  // malformed
            std::string from = pair.substr(0, colon);
            std::string to   = pair.substr(colon + 1);
            if (from.empty() || to.empty()) return {};  // malformed
            result[from] = to;
        }

        return result;
    }

    static std::optional<std::string> consumeFlag(
        const std::vector<std::string>& args, size_t& i, const std::string& flag)
    {
        if (args[i] == flag && i + 1 < args.size()) {
            ++i;
            return args[i++];
        }
        return std::nullopt;
    }
};

} // namespace converter