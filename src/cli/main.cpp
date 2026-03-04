#ifdef _WIN32
    #include <windows.h>
#endif
#include <iostream>
#include <string>
#include <vector>
#include <filesystem>
#include <chrono>
#include <iomanip>
#include <sstream>

#include "../core/Dispatcher.h"
#include "../core/FormatRegistry.h"
#include "ArgParser.h"

namespace fs = std::filesystem;
using namespace converter;

// ── Terminal colors ───────────────────────────────────────────────────────────
#define COL_RESET  "\033[0m"
#define COL_GREEN  "\033[32m"
#define COL_YELLOW "\033[33m"
#define COL_RED    "\033[31m"
#define COL_CYAN   "\033[36m"
#define COL_BOLD   "\033[1m"
#define COL_DIM    "\033[2m"

// ── Helpers ───────────────────────────────────────────────────────────────────
static std::string humanSize(size_t bytes) {
    if (bytes < 1024)       return std::to_string(bytes) + " B";
    if (bytes < 1024*1024)  return std::to_string(bytes / 1024) + " KB";
    return std::to_string(bytes / (1024 * 1024)) + " MB";
}

static void printBanner() {
    std::cout << COL_BOLD
              << "\n  ANYFILE_\n"
              << COL_RESET
              << COL_DIM
              << "  Universal File Converter - v0.1\n\n"
              << COL_RESET;
}

static void printUsage() {
    std::cout
        << "  " COL_BOLD "Usage:" COL_RESET "\n"
        << "    anyfile <input> <output>           Single file, explicit output\n"
        << "    anyfile <input> <ext>              Single file, auto-named output\n"
        << "    anyfile <dir> <ext> [output_dir]   Batch convert directory\n"
        << "    anyfile <dir> <map> [output_dir]   Batch with format map\n"
        << "    anyfile --formats\n"
        << "    anyfile --help\n\n"
        << "    anyfile <dir> <ext> --list         Dry-run: list files that would be converted\n\n"
        << "  " COL_BOLD "Examples:" COL_RESET "\n"
        << "    anyfile video.avi mp4\n"
        << "    anyfile video.avi output.mp4\n"
        << "    anyfile ./videos mp4\n"
        << "    anyfile ./videos mp4 ./output\n"
        << "    anyfile ./videos mp4:mp3,avi:mp4\n"
        << "    anyfile ./videos mp4 -r\n"
        << "    anyfile video.mov output.mp4 --video-codec libx265 --crf 18\n\n"
        << "  " COL_BOLD "Batch options:" COL_RESET "\n"
        << "    -r, --recursive         Recurse into subdirectories\n"
        << "    --f, --force            Overwrite existing output files\n"
        << "    --list                  Dry-run: list files that would be converted\n\n"
        << "  " COL_BOLD "Media options:" COL_RESET "\n"
        << "    --vcodec, --video-codec  <codec>   e.g. libx264, libx265, hevc_nvenc\n"
        << "    --acodec, --audio-codec  <codec>   e.g. aac, libmp3lame, libopus\n"
        << "    --crf          <n>                 Quality: 0 (best) - 51 (worst), default 16\n"
        << "    --vbitrate, --video-bitrate <rate> CBR video bitrate e.g. 8M, 500k\n"
        << "    --vbr1-target  <rate>              VBR 1-pass target e.g. 6M\n"
        << "    --vbr1-max     <rate>              VBR 1-pass max cap e.g. 9M\n"
        << "    --vbr2-target  <rate>              VBR 2-pass target e.g. 6M\n"
        << "    --vbr2-max     <rate>              VBR 2-pass max cap e.g. 9M\n"
        << "    --abitrate, --audio-bitrate <rate> e.g. 320k (default), 192k\n"
        << "    --res, --resolution <WxH>          e.g. 1920x1080, 1280x720\n"
        << "    --framerate, --fps  <fps>          e.g. 24, 30, 60\n"
        << "    --pixel-format <fmt>               e.g. yuv420p, yuv444p\n\n";
}

static void printFormats() {
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

// ── Apply parsed encoding overrides to a job ──────────────────────────────────
static void applyOverrides(ConversionJob& job, const ParsedArgs& args) {
    job.videoCodec   = args.videoCodec;
    job.audioCodec   = args.audioCodec;
    job.videoBitrate = args.videoBitrate;
    job.videoMaxRate = args.videoMaxRate;
    job.audioBitrate = args.audioBitrate;
    job.twoPass      = args.twoPass;
    job.resolution   = args.resolution;
    job.framerate    = args.framerate;
    job.crf          = args.crf;
    job.pixelFormat  = args.pixelFormat;
}

// ── Print encoding overrides if any are active ────────────────────────────────
static void printOverrides(const ParsedArgs& args) {
    if (args.videoCodec  ) std::cout << "  " << COL_DIM << "Video codec   : " << COL_RESET << *args.videoCodec   << "\n";
    if (args.audioCodec  ) std::cout << "  " << COL_DIM << "Audio codec   : " << COL_RESET << *args.audioCodec   << "\n";
    if (args.videoBitrate) std::cout << "  " << COL_DIM << "Video bitrate : " << COL_RESET << *args.videoBitrate << (args.videoMaxRate ? " target" : "") << "\n";
    if (args.videoMaxRate) std::cout << "  " << COL_DIM << "Video max rate: " << COL_RESET << *args.videoMaxRate  << "\n";
    if (args.twoPass     ) std::cout << "  " << COL_DIM << "VBR mode      : " << COL_RESET << "2-pass\n";
    if (args.audioBitrate) std::cout << "  " << COL_DIM << "Audio bitrate : " << COL_RESET << *args.audioBitrate << "\n";
    if (args.resolution  ) std::cout << "  " << COL_DIM << "Resolution    : " << COL_RESET << *args.resolution   << "\n";
    if (args.framerate   ) std::cout << "  " << COL_DIM << "Framerate     : " << COL_RESET << *args.framerate    << "\n";
    if (args.crf         ) std::cout << "  " << COL_DIM << "CRF           : " << COL_RESET << *args.crf          << "\n";
    if (args.pixelFormat ) std::cout << "  " << COL_DIM << "Pixel format  : " << COL_RESET << *args.pixelFormat  << "\n";
}

// ── Check for output conflict, returns true if safe to proceed ────────────────
static bool checkConflict(const fs::path& outputPath, bool force) {
    if (!fs::exists(outputPath)) return true;
    if (force) return true;

    std::cout << "  " << COL_YELLOW << "⚠ Warning: " << COL_RESET
              << "'" << outputPath.filename().string() << "' already exists. "
              << "Use " COL_BOLD "--f" COL_RESET " to overwrite.\n";
    return false;
}

// ── Determine output extension for a file in batch mode ──────────────────────
static std::string resolveTargetExt(const fs::path& file, const ParsedArgs& args) {
    std::string inExt = file.extension().string();
    if (!inExt.empty() && inExt[0] == '.') inExt = inExt.substr(1);
    for (auto& c : inExt) c = std::tolower(c);

    if (!args.formatMap.empty()) {
        auto it = args.formatMap.find(inExt);
        if (it == args.formatMap.end()) return "";  // not in map — skip
        return it->second;
    }

    return args.targetExt;
}

// ── Single file conversion ────────────────────────────────────────────────────
static int runSingle(const ParsedArgs& args) {
    std::cout << "  " << COL_DIM << "Input : " << COL_RESET << args.inputPath.string()  << "\n";
    std::cout << "  " << COL_DIM << "Output: " << COL_RESET << args.outputPath.string() << "\n";
    printOverrides(args);
    std::cout << "\n";

    if (!checkConflict(args.outputPath, args.force)) return 1;

    ConversionJob job;
    job.inputPath  = args.inputPath;
    job.outputPath = args.outputPath;
    job.onProgress = [](float p, const std::string& msg) { printProgress(p, msg); };
    applyOverrides(job, args);

    auto result = Dispatcher::dispatch(std::move(job));
    std::cout << "\n\n";

    if (!result.success) {
        std::cout << "  " << COL_RED << "✗ Failed" << COL_RESET
                  << "  " << result.errorMsg << "\n\n";
        return 1;
    }

    std::cout << "  " << COL_GREEN << "✓ Done" << COL_RESET << "\n\n"
              << "  " << COL_DIM
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

// ── Batch conversion ──────────────────────────────────────────────────────────
static int runBatch(const ParsedArgs& args) {
    if (!args.listOnly)
        fs::create_directories(args.outputDir);

    std::cout << "  " << COL_DIM << "Input dir : " << COL_RESET << args.inputDir.string()  << "\n";
    std::cout << "  " << COL_DIM << "Output dir: " << COL_RESET << args.outputDir.string() << "\n";
    if (!args.targetExt.empty())
        std::cout << "  " << COL_DIM << "Target    : " << COL_RESET << args.targetExt << "\n";
    if (!args.formatMap.empty()) {
        std::cout << "  " << COL_DIM << "Format map: " << COL_RESET;
        bool first = true;
        for (auto& [from, to] : args.formatMap) {
            if (!first) std::cout << ", ";
            std::cout << from << " → " << to;
            first = false;
        }
        std::cout << "\n";
    }
    if (args.recursive) std::cout << "  " << COL_DIM << "Recursive : " << COL_RESET << "yes\n";
    printOverrides(args);
    std::cout << "\n";

    // Collect files
    std::vector<fs::path> files;
    if (args.recursive) {
        for (auto& entry : fs::recursive_directory_iterator(args.inputDir))
            if (entry.is_regular_file())
                files.push_back(entry.path());
    } else {
        for (auto& entry : fs::directory_iterator(args.inputDir))
            if (entry.is_regular_file())
                files.push_back(entry.path());
    }

    if (files.empty()) {
        std::cout << "  " << COL_YELLOW << "⚠ " << COL_RESET << "No files found in input directory.\n\n";
        return 0;
    }

    // --list: dry-run, show what would be converted then exit
    if (args.listOnly) {
        int count = 0;
        for (auto& file : files) {
            std::string toExt = resolveTargetExt(file, args);
            if (toExt.empty()) {
                std::cout << "  " << COL_DIM << "skip  " << COL_RESET
                          << file.filename().string() << "\n";
            } else {
                std::cout << "  " << COL_DIM << file.filename().string() << COL_RESET
                          << " → " << file.stem().string() << "." << toExt << "\n";
                ++count;
            }
        }
        std::cout << "\n  " << COL_BOLD << count << " file" << (count == 1 ? "" : "s")
                  << " would be converted" << COL_RESET << "\n\n";
        return 0;
    }

    // Pre-scan for stem collisions — only among files that will actually be processed
    std::map<std::string, int> stemCount;
    for (auto& file : files) {
        if (resolveTargetExt(file, args).empty()) continue;
        stemCount[file.stem().string()]++;
    }

    int success = 0;
    int skipped = 0;
    int failed  = 0;

    for (auto& file : files) {
        std::string toExt = resolveTargetExt(file, args);

        if (toExt.empty()) {
            std::cout << "  " << COL_DIM << "Skip  " << COL_RESET
                      << file.filename().string() << " (no matching rule)\n";
            ++skipped;
            continue;
        }

        // If multiple input files share the same stem, append source ext to avoid collision
        std::string inExt = file.extension().string();
        if (!inExt.empty() && inExt[0] == '.') inExt = inExt.substr(1);

        bool collision = stemCount[file.stem().string()] > 1;
        std::string outName = collision
            ? file.stem().string() + "_" + inExt + "." + toExt
            : file.stem().string() + "." + toExt;

        // Preserve relative path structure if recursive
        fs::path relPath = fs::relative(file, args.inputDir);
        fs::path outFile = args.outputDir / relPath.parent_path() / outName;
        fs::create_directories(outFile.parent_path());

        if (!checkConflict(outFile, args.force)) {
            ++skipped;
            continue;
        }

        std::cout << "  " << COL_DIM << file.filename().string() << COL_RESET
                  << " → " << outFile.filename().string() << "\n";

        ConversionJob job;
        job.inputPath  = file;
        job.outputPath = outFile;
        job.onProgress = [](float p, const std::string& msg) { printProgress(p, msg); };
        applyOverrides(job, args);

        auto result = Dispatcher::dispatch(std::move(job));
        std::cout << "\n";

        if (!result.success) {
            std::cout << "  " << COL_RED << "  ✗ " << COL_RESET << result.errorMsg << "\n";
            ++failed;
        } else {
            std::cout << "  " << COL_GREEN << "  ✓ " << COL_RESET
                      << COL_DIM
                      << std::fixed << std::setprecision(2)
                      << result.durationSeconds << "s  ·  "
                      << humanSize(result.inputBytes) << " → "
                      << humanSize(result.outputBytes)
                      << COL_RESET << "\n";

            for (auto& w : result.warnings)
                std::cout << "  " << COL_YELLOW << "  ⚠ " << COL_RESET << w << "\n";

            ++success;
        }

        std::cout << "\n";
    }

    // Summary
    std::cout << "  ─────────────────────────────────────\n"
              << "  " << COL_GREEN << "✓ " << success << " converted" << COL_RESET;
    if (failed  > 0) std::cout << "  " << COL_RED    << "✗ " << failed  << " failed"  << COL_RESET;
    if (skipped > 0) std::cout << "  " << COL_YELLOW << "⊘ " << skipped << " skipped" << COL_RESET;
    std::cout << "\n\n";

    return failed > 0 ? 1 : 0;
}

// ── Main ──────────────────────────────────────────────────────────────────────
int main(int argc, char* argv[]) {
    #ifdef _WIN32
        SetConsoleOutputCP(CP_UTF8);
        // Enable ANSI escape code processing (Windows 10 1511+)
        HANDLE hOut = GetStdHandle(STD_OUTPUT_HANDLE);
        DWORD mode = 0;
        if (GetConsoleMode(hOut, &mode))
            SetConsoleMode(hOut, mode | ENABLE_VIRTUAL_TERMINAL_PROCESSING);
    #endif
    printBanner();

    if (argc < 2) {
        printUsage();
        return 0;
    }

    ParsedArgs args = ArgParser::parse(argc, argv);

    if (args.isHelp)    { printUsage();   return 0; }
    if (args.isFormats) { printFormats(); return 0; }

    if (args.hasError) {
        std::cout << "  " << COL_RED << "Error: " << COL_RESET << args.errorMsg << "\n\n";
        printUsage();
        return 1;
    }

    if (args.isBatch) return runBatch(args);
    else              return runSingle(args);
}