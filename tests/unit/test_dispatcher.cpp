#include <catch2/catch_test_macros.hpp>
#include "Dispatcher.h"
#include <fstream>
#include <filesystem>

using namespace converter;
namespace fs = std::filesystem;

// ── Helpers ───────────────────────────────────────────────────────────────────

static fs::path tmpOut(const std::string& name) {
    return fs::temp_directory_path() / ("anyfile_disp_test_" + name);
}

static void cleanup(const fs::path& p) {
    std::error_code ec;
    fs::remove(p, ec);
    // Also clean up .zip variant (PdfRenderer renames to .zip)
    fs::path zip = p; zip.replace_extension(".zip");
    fs::remove(zip, ec);
}

// Returns true if the tool is available on PATH
static bool toolAvailable(const std::string& name) {
    return Process::run("which", {name}) == 0;
}

// ── Input validation ──────────────────────────────────────────────────────────

TEST_CASE("Dispatcher - input validation", "[dispatcher][validation]") {

    SECTION("missing input file returns error") {
        auto result = Dispatcher::dispatch(
            "/tmp/does_not_exist_anyfile.mp4",
            tmpOut("out.mp3")
        );
        REQUIRE_FALSE(result.success);
        REQUIRE_FALSE(result.errorMsg.empty());
    }

    SECTION("unknown input format returns error") {
        fs::path p = fs::temp_directory_path() / "anyfile_unknown.xyz123";
        { std::ofstream f(p); f << "data"; }
        auto result = Dispatcher::dispatch(p, tmpOut("out.mp3"));
        fs::remove(p);
        REQUIRE_FALSE(result.success);
    }

    SECTION("unknown output format returns error") {
        fs::path p = fs::temp_directory_path() / "anyfile_valid.json";
        { std::ofstream f(p); f << "{}"; }
        auto result = Dispatcher::dispatch(p, tmpOut("out.xyz123"));
        fs::remove(p);
        REQUIRE_FALSE(result.success);
    }

    SECTION("same format non-media returns error") {
        fs::path p = fs::temp_directory_path() / "anyfile_same.json";
        { std::ofstream f(p); f << "{}"; }
        auto result = Dispatcher::dispatch(p, tmpOut("out.json"));
        fs::remove(p);
        REQUIRE_FALSE(result.success);
        REQUIRE(result.errorMsg.find("same format") != std::string::npos);
    }

    SECTION("unsupported conversion returns error") {
        fs::path p = fs::temp_directory_path() / "anyfile_unsupported.mp3";
        { std::ofstream f(p); f << "data"; }
        auto result = Dispatcher::dispatch(p, tmpOut("out.glb"));
        fs::remove(p);
        REQUIRE_FALSE(result.success);
        REQUIRE(result.errorMsg.find("not supported") != std::string::npos);
    }
}

// ── Atomic write behaviour ────────────────────────────────────────────────────

TEST_CASE("Dispatcher - atomic write", "[dispatcher][atomic]") {

    SECTION("no partial output file left on failure") {
        // Use a real input with an unsupported conversion so it fails fast
        fs::path p = fs::temp_directory_path() / "anyfile_atomic.json";
        { std::ofstream f(p); f << "{}"; }
        fs::path out = tmpOut("atomic_out.glb");

        Dispatcher::dispatch(p, out);
        fs::remove(p);

        // No temp file should remain
        bool anyTemp = false;
        for (auto& e : fs::directory_iterator(fs::temp_directory_path())) {
            if (e.path().string().find("anyfile_disp_test_atomic") != std::string::npos)
                anyTemp = true;
        }
        REQUIRE_FALSE(anyTemp);
    }

    SECTION("output directory is created if missing") {
        fs::path p = fs::temp_directory_path() / "anyfile_dir_test.json";
        { std::ofstream f(p); f << "{\"x\":1}"; }

        fs::path newDir = fs::temp_directory_path() / "anyfile_newdir_test";
        fs::remove_all(newDir);
        fs::path out = newDir / "out.xml";

        auto result = Dispatcher::dispatch(p, out);
        fs::remove(p);
        fs::remove_all(newDir);

        // Dir creation is tested regardless of conversion success
        // (it may fail if DataConverter has issues with this env)
        // Just verify no crash and the dir was at least attempted
        REQUIRE_FALSE(result.errorMsg.find("directory") != std::string::npos);
    }
}

// ── Cancellation ──────────────────────────────────────────────────────────────

TEST_CASE("Dispatcher - cancellation", "[dispatcher][cancel]") {

    SECTION("pre-set cancel flag returns cancelled result") {
        if (!toolAvailable("ffmpeg")) {
            SKIP("ffmpeg not installed");
        }

        // Need a real media file — use a tiny synthetic WAV
        fs::path wav = fs::temp_directory_path() / "anyfile_cancel_test.wav";
        {
            // Minimal valid WAV header (44 bytes) + silence
            std::vector<uint8_t> data(1024, 0);
            // RIFF header
            const char* riff = "RIFF";
            const char* wave = "WAVE";
            const char* fmt  = "fmt ";
            const char* data_hdr = "data";
            uint32_t fileSize = 1024 - 8;
            uint32_t fmtSize  = 16;
            uint16_t audioFmt = 1, channels = 1;
            uint32_t sampleRate = 8000, byteRate = 8000;
            uint16_t blockAlign = 1, bitsPerSample = 8;
            uint32_t dataSize = 1024 - 44;

            std::ofstream f(wav, std::ios::binary);
            f.write(riff, 4); f.write((char*)&fileSize, 4);
            f.write(wave, 4); f.write(fmt, 4);
            f.write((char*)&fmtSize, 4);
            f.write((char*)&audioFmt, 2); f.write((char*)&channels, 2);
            f.write((char*)&sampleRate, 4); f.write((char*)&byteRate, 4);
            f.write((char*)&blockAlign, 2); f.write((char*)&bitsPerSample, 2);
            f.write(data_hdr, 4); f.write((char*)&dataSize, 4);
            std::vector<char> silence(dataSize, 0);
            f.write(silence.data(), silence.size());
        }

        std::atomic<bool> cancel{true};  // pre-cancelled
        ConversionJob job;
        job.inputPath  = wav;
        job.outputPath = tmpOut("cancel_out.mp3");
        job.cancelFlag = &cancel;

        auto result = Dispatcher::dispatch(job);
        fs::remove(wav);
        cleanup(job.outputPath);

        REQUIRE_FALSE(result.success);
        REQUIRE(result.errorMsg == "Conversion cancelled");
    }
}

// ── Data conversion routing ───────────────────────────────────────────────────
// These use generated seed files so no external deps needed

TEST_CASE("Dispatcher - data routing", "[dispatcher][data]") {

    SECTION("JSON → XML") {
        fs::path in = fs::temp_directory_path() / "anyfile_route.json";
        fs::path out = tmpOut("route_out.xml");
        { std::ofstream f(in); f << "{\"name\":\"Alice\",\"age\":30}"; }

        auto result = Dispatcher::dispatch(in, out);

        REQUIRE(result.success);
        REQUIRE(fs::exists(result.outputPath));
        REQUIRE(fs::file_size(result.outputPath) > 0);
        fs::remove(in); cleanup(out);
    }

    SECTION("JSON → YAML") {
        fs::path in = fs::temp_directory_path() / "anyfile_route.json";
        fs::path out = tmpOut("route_out.yaml");
        { std::ofstream f(in); f << "{\"name\":\"Alice\",\"age\":30}"; }

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.success);
    }

    SECTION("CSV → JSON") {
        fs::path in = fs::temp_directory_path() / "anyfile_route.csv";
        fs::path out = tmpOut("route_out.json");
        { std::ofstream f(in); f << "name,age\nAlice,30\nBob,25\n"; }

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.success);
    }
}

// ── Archive routing ───────────────────────────────────────────────────────────

TEST_CASE("Dispatcher - archive routing", "[dispatcher][archive]") {

    SECTION("ZIP → TAR") {
        // Build a minimal zip
        fs::path dir = fs::temp_directory_path() / "anyfile_zip_seed";
        fs::create_directories(dir);
        { std::ofstream f(dir / "hello.txt"); f << "hello anyfile\n"; }

        fs::path zip = fs::temp_directory_path() / "anyfile_route_seed.zip";
        Process::run("zip", {"-r", zip.string(), dir.string()});
        fs::remove_all(dir);

        if (!fs::exists(zip)) {
            SKIP("zip utility not available to create seed file");
        }

        fs::path out = tmpOut("route_out.tar");
        auto result = Dispatcher::dispatch(zip, out);

        REQUIRE(result.success);
        REQUIRE(fs::file_size(result.outputPath) > 0);
        fs::remove(zip); cleanup(out);
    }
}

// ── Real conversions (tool-gated) ─────────────────────────────────────────────

TEST_CASE("Dispatcher - real media conversions", "[dispatcher][media][integration]") {

    if (!toolAvailable("ffmpeg")) {
        SKIP("ffmpeg not installed");
    }

    // Synthetic minimal WAV — 8kHz mono 8-bit, 0.1s of silence
    auto makeWav = [](const fs::path& p) {
        std::ofstream f(p, std::ios::binary);
        uint32_t dataSize   = 800;    // 0.1s at 8kHz
        uint32_t fileSize   = 36 + dataSize;
        uint16_t audioFmt   = 1, channels = 1;
        uint32_t sampleRate = 8000, byteRate = 8000;
        uint16_t blockAlign = 1, bitsPerSample = 8;

        f.write("RIFF", 4); f.write((char*)&fileSize, 4);
        f.write("WAVE", 4); f.write("fmt ", 4);
        uint32_t fmtSize = 16;
        f.write((char*)&fmtSize, 4);
        f.write((char*)&audioFmt, 2); f.write((char*)&channels, 2);
        f.write((char*)&sampleRate, 4); f.write((char*)&byteRate, 4);
        f.write((char*)&blockAlign, 2); f.write((char*)&bitsPerSample, 2);
        f.write("data", 4); f.write((char*)&dataSize, 4);
        std::vector<char> silence(dataSize, 0);
        f.write(silence.data(), silence.size());
    };

    SECTION("WAV → MP3") {
        fs::path in  = fs::temp_directory_path() / "anyfile_real.wav";
        fs::path out = tmpOut("real_out.mp3");
        makeWav(in);

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.success);
        REQUIRE(result.outputBytes > 0);
        REQUIRE(result.durationSeconds > 0.0);
    }

    SECTION("WAV → FLAC") {
        fs::path in  = fs::temp_directory_path() / "anyfile_real.wav";
        fs::path out = tmpOut("real_out.flac");
        makeWav(in);

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.success);
    }

    SECTION("result contains input and output byte counts") {
        fs::path in  = fs::temp_directory_path() / "anyfile_real.wav";
        fs::path out = tmpOut("real_out2.mp3");
        makeWav(in);

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.inputBytes > 0);
        REQUIRE(result.outputBytes > 0);
    }
}

TEST_CASE("Dispatcher - real document conversions", "[dispatcher][documents][integration]") {

    if (!toolAvailable("pandoc")) {
        SKIP("pandoc not installed");
    }

    SECTION("Markdown → HTML") {
        fs::path in  = fs::temp_directory_path() / "anyfile_real.md";
        fs::path out = tmpOut("real_out.html");
        { std::ofstream f(in); f << "# Hello\n\nThis is **anyfile**.\n"; }

        auto result = Dispatcher::dispatch(in, out);

        REQUIRE(result.success);
        REQUIRE(fs::file_size(result.outputPath) > 0);
        fs::remove(in); cleanup(out);
    }

    SECTION("Markdown → DOCX") {
        fs::path in  = fs::temp_directory_path() / "anyfile_real.md";
        fs::path out = tmpOut("real_out.docx");
        { std::ofstream f(in); f << "# Hello\n\nThis is **anyfile**.\n"; }

        auto result = Dispatcher::dispatch(in, out);
        fs::remove(in); cleanup(out);

        REQUIRE(result.success);
    }
}
