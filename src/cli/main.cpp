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
        << "    converter <input> <output>\n"
        << "    converter <input> --to <ext>\n"
        << "    converter --formats\n"
        << "    converter --help\n\n"
        << "  " COL_BOLD "Examples:" COL_RESET "\n"
        << "    converter video.mp4 audio.mp3\n"
        << "    converter model.fbx model.glb\n"
        << "    converter image.png --to webp\n"
        << "    converter photo.heic --to jpg\n\n";
}

static void printFormats() {
    auto& reg = FormatRegistry::instance();

    struct Group { std::string name; std::vector<std::string> exts; };
    std::vector<Group> groups = {
        { "Images",   {"png","jpg","webp","bmp","tiff","gif","heic","avif","exr","tga","svg"} },
        { "Video",    {"mp4","mov","avi","mkv","webm","flv","wmv","ogv"} },
        { "Audio",    {"mp3","wav","flac","aac","ogg","opus","m4a"} },
        { "3D",       {"fbx","obj","glb","gltf","stl","dae","ply","3ds","usd"} },
        { "Archives", {"zip","tar","gz","bz2","xz","7z","rar","zst"} },
        { "Data",     {"json","xml","yaml","csv","tsv","toml"} },
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
              << "          " // clear leftover chars
              << std::flush;
}

// ── Main ──────────────────────────────────────────────────────────────────────
int main(int argc, char* argv[]) {
    printBanner();

    if (argc < 2) {
        printUsage();
        return 0;
    }

    std::string arg1 = argv[1];

    // Flags
    if (arg1 == "--help" || arg1 == "-h") { printUsage();   return 0; }
    if (arg1 == "--formats")              { printFormats(); return 0; }

    // Parse: converter <input> <output>  OR  converter <input> --to <ext>
    if (argc < 3) {
        std::cerr << COL_RED << "  Error: " << COL_RESET
                  << "Expected output file or --to <ext>\n\n";
        printUsage();
        return 1;
    }

    fs::path inputPath  = arg1;
    fs::path outputPath;

    std::string arg2 = argv[2];
    if (arg2 == "--to" || arg2 == "-t") {
        if (argc < 4) {
            std::cerr << COL_RED << "  Error: " << COL_RESET << "--to requires an extension\n";
            return 1;
        }
        std::string ext = argv[3];
        if (ext[0] == '.') ext = ext.substr(1);
        outputPath = inputPath.stem().string() + "." + ext;
    } else {
        outputPath = arg2;
    }

    // Print job info
    std::cout << "  " << COL_DIM << "Input : " << COL_RESET << inputPath.string()  << "\n";
    std::cout << "  " << COL_DIM << "Output: " << COL_RESET << outputPath.string() << "\n\n";

    // Dispatch
    auto result = Dispatcher::dispatch(
        inputPath,
        outputPath,
        [](float p, const std::string& msg) { printProgress(p, msg); }
    );

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
