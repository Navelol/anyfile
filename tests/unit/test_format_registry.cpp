#include <catch2/catch_test_macros.hpp>
#include "FormatRegistry.h"
#include <fstream>
#include <filesystem>

using namespace converter;
namespace fs = std::filesystem;

// ── Helpers ───────────────────────────────────────────────────────────────────

// Write raw bytes to a temp file, return its path
static fs::path writeTempFile(const std::string& name,
                               const std::vector<uint8_t>& bytes) {
    fs::path p = fs::temp_directory_path() / name;
    std::ofstream f(p, std::ios::binary);
    f.write(reinterpret_cast<const char*>(bytes.data()), bytes.size());
    return p;
}

// ── Extension detection ───────────────────────────────────────────────────────

TEST_CASE("FormatRegistry - extension detection", "[registry][extension]") {
    auto& reg = FormatRegistry::instance();

    SECTION("known extensions are detected") {
        REQUIRE(reg.detectByExtension("file.mp4"));
        REQUIRE(reg.detectByExtension("file.json"));
        REQUIRE(reg.detectByExtension("file.zip"));
        REQUIRE(reg.detectByExtension("file.docx"));
        REQUIRE(reg.detectByExtension("file.epub"));
        REQUIRE(reg.detectByExtension("file.glb"));
    }

    SECTION("unknown extension returns nullopt") {
        REQUIRE_FALSE(reg.detectByExtension("file.xyz"));
        REQUIRE_FALSE(reg.detectByExtension("file.unknown"));
        REQUIRE_FALSE(reg.detectByExtension("file"));
    }

    SECTION("extension is case-insensitive") {
        REQUIRE(reg.detectByExtension("file.MP4"));
        REQUIRE(reg.detectByExtension("file.PNG"));
        REQUIRE(reg.detectByExtension("file.JSON"));
    }

    SECTION("correct category is assigned") {
        REQUIRE(reg.detectByExtension("file.mp4")->category  == Category::Video);
        REQUIRE(reg.detectByExtension("file.mp3")->category  == Category::Audio);
        REQUIRE(reg.detectByExtension("file.png")->category  == Category::Image);
        REQUIRE(reg.detectByExtension("file.zip")->category  == Category::Archive);
        REQUIRE(reg.detectByExtension("file.json")->category == Category::Data);
        REQUIRE(reg.detectByExtension("file.pdf")->category  == Category::Document);
        REQUIRE(reg.detectByExtension("file.epub")->category == Category::Ebook);
        REQUIRE(reg.detectByExtension("file.glb")->category  == Category::Model3D);
    }

    SECTION("ext field is lowercase without dot") {
        auto fmt = reg.detectByExtension("file.MP4");
        REQUIRE(fmt->ext == "mp4");
    }
}

// ── canConvert ────────────────────────────────────────────────────────────────

TEST_CASE("FormatRegistry - canConvert", "[registry][targets]") {
    auto& reg = FormatRegistry::instance();

    SECTION("valid conversions are allowed") {
        REQUIRE(reg.canConvert("mp4",  "mp3"));
        REQUIRE(reg.canConvert("png",  "jpg"));
        REQUIRE(reg.canConvert("json", "xml"));
        REQUIRE(reg.canConvert("zip",  "7z"));
        REQUIRE(reg.canConvert("docx", "pdf"));
        REQUIRE(reg.canConvert("epub", "mobi"));
        REQUIRE(reg.canConvert("obj",  "glb"));
    }

    SECTION("nonsense conversions are rejected") {
        REQUIRE_FALSE(reg.canConvert("mp3",  "glb"));
        REQUIRE_FALSE(reg.canConvert("json", "mp4"));
        REQUIRE_FALSE(reg.canConvert("zip",  "epub"));
    }

    SECTION("unknown format returns false") {
        REQUIRE_FALSE(reg.canConvert("xyz", "mp4"));
        REQUIRE_FALSE(reg.canConvert("mp4", "xyz"));
    }
}

// ── Magic-number / byte detection ─────────────────────────────────────────────

TEST_CASE("FormatRegistry - magic number detection", "[registry][magic]") {
    auto& reg = FormatRegistry::instance();

    SECTION("PNG magic bytes detected regardless of extension") {
        // PNG magic: 89 50 4E 47 0D 0A 1A 0A
        std::vector<uint8_t> png = {
            0x89,'P','N','G',0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,'I','H','D','R'
        };
        auto p = writeTempFile("magic_test.dat", png);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Image);
        REQUIRE(fmt->ext == "png");
    }

    SECTION("ZIP magic bytes detected with wrong extension") {
        // PK zip magic: 50 4B 03 04
        std::vector<uint8_t> zip = {'P','K',0x03,0x04,0x14,0x00,0x00,0x00};
        auto p = writeTempFile("magic_test.bak", zip);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Archive);
        REQUIRE(fmt->ext == "zip");
    }

    SECTION("PDF magic bytes detected with wrong extension") {
        std::vector<uint8_t> pdf = {'%','P','D','F','-','1','.','4'};
        auto p = writeTempFile("magic_test.xyz", pdf);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Document);
        REQUIRE(fmt->ext == "pdf");
    }

    SECTION("JPEG magic bytes detected") {
        std::vector<uint8_t> jpg = {0xFF,0xD8,0xFF,0xE0,0x00,0x10,'J','F','I','F'};
        auto p = writeTempFile("magic_test.dat", jpg);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Image);
        REQUIRE(fmt->ext == "jpeg");
    }

    SECTION("GZ magic bytes detected") {
        std::vector<uint8_t> gz = {0x1F,0x8B,0x08,0x00,0x00,0x00,0x00,0x00};
        auto p = writeTempFile("magic_test.dat", gz);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Archive);
        REQUIRE(fmt->ext == "gz");
    }

    SECTION("FLAC magic bytes detected") {
        std::vector<uint8_t> flac = {'f','L','a','C',0x00,0x00,0x00,0x22};
        auto p = writeTempFile("magic_test.dat", flac);
        auto fmt = reg.detect(p);
        fs::remove(p);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->category == Category::Audio);
        REQUIRE(fmt->ext == "flac");
    }

    SECTION("inconclusive bytes fall back to extension") {
        // Random bytes that don't match any magic signature
        std::vector<uint8_t> noise = {0x00,0x01,0x02,0x03,0x04,0x05,0x06,0x07};
        auto p = writeTempFile("fallback_test.mp3", noise);
        auto fmt = reg.detect(p);
        fs::remove(p);
        // Should fall back to extension
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->ext == "mp3");
    }

    SECTION("output path (non-existent file) uses extension only") {
        fs::path fake = "/tmp/does_not_exist_anyfile_test.json";
        auto fmt = reg.detect(fake);
        REQUIRE(fmt.has_value());
        REQUIRE(fmt->ext == "json");
        REQUIRE(fmt->category == Category::Data);
    }
}
