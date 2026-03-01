#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include <chrono>
#include <iomanip>
#include <sstream>

#include "../core/Dispatcher.h"
#include "../core/FormatRegistry.h"

namespace fs = std::filesystem;
using namespace converter;

// ── Terminal colors ───────────────────────────────────────────────────────────
#ifdef PLATFORM_WINDOWS
  #define COL_RESET  ""
  #define COL_GREEN  ""
  #define COL_YELLOW ""
  #define COL_RED    ""
  #define COL_CYAN   ""
  #define COL_BOLD   ""
  #define COL_DIM    ""
#else
  #define COL_RESET  "\033[0m"
  #define COL_GREEN  "\033[32m"
  #define COL_YELLOW "\033[33m"
  #define COL_RED    "\033[31m"
  #define COL_CYAN   "\033[36m"
  #define COL_BOLD   "\033[1m"
  #define COL_DIM    "\033[2m"
#endif

// ── Helpers ───────────────────────────────────────────────────────────────────
static std::string humanSize(size_t bytes) {
    if (bytes < 1024)       return std::to_string(bytes) + " B";
    if (bytes < 1024*1024)  return std::to_string(bytes/1024) + " KB";
    return std::to_string(bytes/(1024*1024)) + " MB";
}

static void printBanner() {
    std::cout << COL_BOLD
              << "\n  CONVERT_\n"
              << COL_RESET
              << COL_DIM
              << "  Universal File Converter — v0.1\n\n"
              << COL_RESET;
}

static void printUsage() {
    std::cout
        << "  " COL_BOLD "Usage:" COL_RESET "\n"
        << "    converter <input> <output> [options]\n"
        << "    converter <input> --to <ext> [options]\n"
        << "    converter --formats\n"
        << "    converter --help\n\n"
        << "  " COL_BOLD "Examples:" COL_RESET "\n"
        << "    converter video.mp4 audio.mp3\n"
        << "    converter model.fbx model.glb\n"
        << "    converter image.png --to webp\n"
        << "    converter video.mov output.mp4 --video-codec libx265 --crf 18\n"
        << "    converter video.mp4 output.mp4 --resolution 1280x720 --framerate 30\n"
        << "    converter audio.wav output.mp3 --audio-bitrate 320k\n\n"
        << "  " COL_BOLD "Media options:" COL_RESET "\n"
        << "    --video-codec  <codec>    e.g. libx264, libx265, vp9, mpeg4\n"
        << "    --audio-codec  <codec>    e.g. aac, libmp3lame, libopus, flac\n"
        << "    --video-bitrate <rate>    e.g. 2M, 500k\n"
        << "    --audio-bitrate <rate>    e.g. 192k, 320k\n"
        << "    --resolution   <WxH>      e.g. 1920x1080, 1280x720\n"
        << "    --framerate    <fps>      e.g. 24, 30, 60\n"
        << "    --crf          <n>        Quality: 0 (best) – 51 (worst), default 23\n"
        << "    --pixel-format <fmt>      e.g. yuv420p, yuv444p\n\n";
}

static void printFormats() {
    auto& reg = FormatRegistry::instance();

    struct Group { std::string name; std::vector<std::string> exts; };
    std::vector<Group> groups = {
        { "Images",    {"png","jpg","webp","bmp","tiff","gif","heic","avif","exr","tga","svg"} },
        { "Video",     {"mp4","mov","avi","mkv","webm","flv","wmv","ogv"} },
        { "Audio",     {"mp3","wav","flac","aac","ogg","opus","m4a"} },
        { "3D",        {"fbx","obj","glb","gltf","stl","dae","ply","3ds","usd"} },
        { "Archives",  {"zip","tar","gz","bz2","xz","7z","rar","zst"} },
        { "Data",      {"json","xml","yaml","csv","tsv","toml"} },
        { "Documents", {"pdf","docx","odt","rtf","xlsx","pptx","html","md"} },
        { "Ebooks",    {"epub","mobi","azw3","fb2","djvu"} },
    };

    std::cout << COL_BOLD << "  Supported formats:\n\n" << COL_RESET;
    for (auto& g : groups) {
        std::cout << "  " << COL_CYAN << std::left << std::setw(12) << g.name << COL_RESET;
        for (auto& e : g.exts)
            std::cout << COL_DIM << "." << COL_RESET << e << "  ";
        std::cout << "\n";
    }
    std::cout << "\n";
}

// Simple inline progress bar for the terminal
static void printProgress(float progress, const std::string& msg) {
    const int barWidth = 30;
    int filled = (int)(progress * barWidth);

    std::cout << "\r  [";
    for (int i = 0; i < barWidth; i++)
        std::cout << (i < filled ? "█" : "░");
    std::cout << "] "
              << std::setw(3) << (int)(progress * 100) << "% "
              << COL_DIM << msg << COL_RESET
              << "          "
              << std::flush;
}

// ── Argument parsing helpers ──────────────────────────────────────────────────

// Returns the value for a named flag, or std::nullopt if not found.
// Handles both "--flag value" and advances i past the value.
static std::optional<std::string> consumeFlag(
    const std::vector<std::string>& args, size_t& i, const std::string& flag)
{
    if (args[i] == flag && i + 1 < args.size()) {
        ++i;
        return args[i];
    }
    return std::nullopt;
}

// ── Main ──────────────────────────────────────────────────────────────────────
int main(int argc, char* argv[]) {
    printBanner();

    if (argc < 2) {
        printUsage();
        return 0;
    }

    std::vector<std::string> args(argv + 1, argv + argc);
    size_t i = 0;

    std::string arg1 = args[i++];

    // Flags
    if (arg1 == "--help" || arg1 == "-h") { printUsage();   return 0; }
    if (arg1 == "--formats")              { printFormats(); return 0; }

    if (i >= args.size()) {
        std::cerr << COL_RED << "  Error: " << COL_RESET
                  << "Expected output file or --to <ext>\n\n";
        printUsage();
        return 1;
    }

    fs::path inputPath  = arg1;
    fs::path outputPath;

    std::string arg2 = args[i++];
    if (arg2 == "--to" || arg2 == "-t") {
        if (i >= args.size()) {
            std::cerr << COL_RED << "  Error: " << COL_RESET << "--to requires an extension\n";
            return 1;
        }
        std::string ext = args[i++];
        if (ext[0] == '.') ext = ext.substr(1);
        outputPath = inputPath.stem().string() + "." + ext;
    } else {
        outputPath = arg2;
    }

    // ── Parse optional media flags ────────────────────────────────────────────
    ConversionJob job;
    job.inputPath  = inputPath;
    job.outputPath = outputPath;

    while (i < args.size()) {
        if (auto v = consumeFlag(args, i, "--video-codec"))   { job.videoCodec   = v; }
        else if (auto v = consumeFlag(args, i, "--audio-codec"))   { job.audioCodec   = v; }
        else if (auto v = consumeFlag(args, i, "--video-bitrate")) { job.videoBitrate = v; }
        else if (auto v = consumeFlag(args, i, "--audio-bitrate")) { job.audioBitrate = v; }
        else if (auto v = consumeFlag(args, i, "--resolution"))    { job.resolution   = v; }
        else if (auto v = consumeFlag(args, i, "--framerate"))     { job.framerate    = v; }
        else if (auto v = consumeFlag(args, i, "--pixel-format"))  { job.pixelFormat  = v; }
        else if (auto v = consumeFlag(args, i, "--crf")) {
            try { job.crf = std::stoi(*v); }
            catch (...) {
                std::cerr << COL_RED << "  Error: " << COL_RESET
                          << "--crf requires an integer (e.g. 23)\n";
                return 1;
            }
        } else {
            std::cerr << COL_YELLOW << "  Warning: " << COL_RESET
                      << "Unknown option '" << args[i] << "' — ignoring\n";
        }
        ++i;
    }

    // Print job info
    std::cout << "  " << COL_DIM << "Input : " << COL_RESET << inputPath.string()  << "\n";
    std::cout << "  " << COL_DIM << "Output: " << COL_RESET << outputPath.string() << "\n";

    // Print any active overrides so user knows what's being applied
    if (job.videoCodec   ) std::cout << "  " << COL_DIM << "Video codec   : " << COL_RESET << *job.videoCodec    << "\n";
    if (job.audioCodec   ) std::cout << "  " << COL_DIM << "Audio codec   : " << COL_RESET << *job.audioCodec    << "\n";
    if (job.videoBitrate ) std::cout << "  " << COL_DIM << "Video bitrate : " << COL_RESET << *job.videoBitrate  << "\n";
    if (job.audioBitrate ) std::cout << "  " << COL_DIM << "Audio bitrate : " << COL_RESET << *job.audioBitrate  << "\n";
    if (job.resolution   ) std::cout << "  " << COL_DIM << "Resolution    : " << COL_RESET << *job.resolution    << "\n";
    if (job.framerate    ) std::cout << "  " << COL_DIM << "Framerate     : " << COL_RESET << *job.framerate     << "\n";
    if (job.crf          ) std::cout << "  " << COL_DIM << "CRF           : " << COL_RESET << *job.crf           << "\n";
    if (job.pixelFormat  ) std::cout << "  " << COL_DIM << "Pixel format  : " << COL_RESET << *job.pixelFormat   << "\n";

    std::cout << "\n";

    // Dispatch
    job.onProgress = [](float p, const std::string& msg) { printProgress(p, msg); };

    auto result = Dispatcher::dispatch(std::move(job));

    std::cout << "\n\n";

    if (!result.success) {
        std::cout << "  " << COL_RED << "✗ Failed" << COL_RESET
                  << "  " << result.errorMsg << "\n\n";
        return 1;
    }

    // Success summary
    std::cout << "  " << COL_GREEN << "✓ Done" << COL_RESET << "\n\n";

    std::cout << "  " << COL_DIM
              << std::fixed << std::setprecision(2)
              << result.durationSeconds << "s  ·  "
              << humanSize(result.inputBytes) << " → "
              << humanSize(result.outputBytes)
              << COL_RESET << "\n";

    if (!result.warnings.empty()) {
        std::cout << "\n";
        for (auto& w : result.warnings)
            std::cout << "  " << COL_YELLOW << "⚠ " << COL_RESET << w << "\n";
    }

    std::cout << "\n";
    return 0;
}