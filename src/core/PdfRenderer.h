#pragma once

#include "Types.h"
#include "Process.h"
#include <archive.h>
#include <archive_entry.h>
#include <chrono>
#include <vector>
#include <fstream>

namespace converter {

class PdfRenderer {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        const std::string& outExt = job.outputFormat.ext;

        std::string fmtFlag = ppmFlag(outExt);
        if (fmtFlag.empty())
            return ConversionResult::err(
                "Unsupported image output format for PDF rendering: ." + outExt);

        if (job.onProgress) job.onProgress(0.05f, "Rendering PDF pages...");

        fs::path tempDir = fs::temp_directory_path() / ("anyfile_pdf_" + std::to_string(
            std::chrono::steady_clock::now().time_since_epoch().count()));
        fs::create_directories(tempDir);

        fs::path pagePrefix = tempDir / "page";

        int rc = Process::runCancellable("pdftoppm", {
            fmtFlag,
            "-r", "150",
            job.inputPath.string(),
            pagePrefix.string()
        }, job.cancelFlag);

        if (rc == -2) { fs::remove_all(tempDir); return ConversionResult::cancelled(); }
        if (rc != 0)  {
            fs::remove_all(tempDir);
            return ConversionResult::err("pdftoppm failed — is poppler-utils installed?");
        }

        // Check cancel before the zip step
        if (job.cancelFlag && job.cancelFlag->load()) {
            fs::remove_all(tempDir);
            return ConversionResult::cancelled();
        }

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
        if (ext == "webp") return "-jpeg";
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