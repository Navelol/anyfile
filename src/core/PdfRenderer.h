#pragma once

#include "Types.h"
#include <archive.h>
#include <archive_entry.h>
#include <chrono>
#include <cstdlib>
#include <vector>
#include <fstream>

namespace converter {

class PdfRenderer {
private:
#ifdef _WIN32
    static constexpr const char* DEVNULL = "2>NUL";
    static constexpr const char* AND_CMD = " & ";
    static constexpr const char* RM_CMD  = "del /f /q ";
#else
    static constexpr const char* DEVNULL = "2>/dev/null";
    static constexpr const char* AND_CMD = " && ";
    static constexpr const char* RM_CMD  = "rm -f ";
#endif

public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        const std::string& outExt = job.outputFormat.ext;

        // pdftoppm format flag
        std::string fmtFlag = ppmFlag(outExt);
        if (fmtFlag.empty())
            return ConversionResult::err("Unsupported image output format for PDF rendering: ." + outExt);

        if (job.onProgress) job.onProgress(0.05f, "Rendering PDF pages...");

        // Work in a temp directory
        fs::path tempDir = fs::temp_directory_path() / ("everyfile_pdf_" + std::to_string(
            std::chrono::steady_clock::now().time_since_epoch().count()));
        fs::create_directories(tempDir);

        fs::path pagePrefix = tempDir / "page";

        // Run pdftoppm: outputs page-1.png, page-2.png, etc.
        std::string cmd =
            "pdftoppm " + fmtFlag +
            " -r 150" +                               // 150 DPI — good balance of quality/size
            " \"" + job.inputPath.string() + "\"" +
            " \"" + pagePrefix.string() + "\"" +
            " " + DEVNULL;

        int ret = std::system(cmd.c_str());
        if (ret != 0) {
            fs::remove_all(tempDir);
            return ConversionResult::err("pdftoppm failed — is poppler-utils installed?");
        }

        // Collect output files (sorted so pages are in order)
        std::vector<fs::path> pages;
        for (auto& entry : fs::directory_iterator(tempDir)) {
            if (entry.is_regular_file())
                pages.push_back(entry.path());
        }

        if (pages.empty()) {
            fs::remove_all(tempDir);
            return ConversionResult::err("pdftoppm produced no output files");
        }

        std::sort(pages.begin(), pages.end());

        if (job.onProgress) job.onProgress(0.6f, "Packing pages into zip...");

        // Output path: force .zip extension regardless of what was requested
        fs::path zipOut = job.outputPath;
        zipOut.replace_extension(".zip");

        std::string packErr = packZip(pages, zipOut);
        if (!packErr.empty()) {
            fs::remove_all(tempDir);
            return ConversionResult::err("Failed to create zip: " + packErr);
        }

        fs::remove_all(tempDir);

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result        = ConversionResult::ok(zipOut, secs);
        result.inputBytes  = fs::file_size(job.inputPath);
        result.outputBytes = fs::file_size(zipOut);

        // Warn if we silently changed the extension
        if (job.outputPath.extension() != ".zip") {
            result.warnings.push_back(
                "Output is a zip of page images. Extension changed to .zip "
                "(requested: " + job.outputPath.extension().string() + ")"
            );
        }

        return result;
    }

private:
    static std::string ppmFlag(const std::string& ext) {
        if (ext == "png")  return "-png";
        if (ext == "jpg")  return "-jpeg";
        if (ext == "jpeg") return "-jpeg";
        if (ext == "webp") return "-jpeg"; // pdftoppm doesn't support webp; fall back to jpeg
        return "";
    }

    static std::string packZip(const std::vector<fs::path>& files, const fs::path& dest) {
        struct archive* a = archive_write_new();
        archive_write_set_format_zip(a);

        if (archive_write_open_filename(a, dest.string().c_str()) != ARCHIVE_OK) {
            std::string err = archive_error_string(a);
            archive_write_free(a);
            return err;
        }

        for (auto& filePath : files) {
            struct archive_entry* entry = archive_entry_new();
            archive_entry_set_pathname(entry, filePath.filename().string().c_str());
            archive_entry_set_size(entry, fs::file_size(filePath));
            archive_entry_set_filetype(entry, AE_IFREG);
            archive_entry_set_perm(entry, 0644);

            archive_write_header(a, entry);

            std::ifstream f(filePath, std::ios::binary);
            std::vector<char> buf(8192);
            while (f.read(buf.data(), buf.size()) || f.gcount() > 0)
                archive_write_data(a, buf.data(), (size_t)f.gcount());

            archive_entry_free(entry);
        }

        archive_write_close(a);
        archive_write_free(a);
        return "";
    }
};

} // namespace converter