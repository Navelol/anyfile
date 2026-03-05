#pragma once

#include "Types.h"
#include <archive.h>
#include <archive_entry.h>
#include <chrono>
#include <vector>
#include <cstring>

namespace converter {

class ArchiveConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.1f, "Reading archive...");

        // Step 1: extract input archive to a temp directory
        fs::path tempDir = makeTempName("everyfile_");
        fs::create_directories(tempDir);

        auto extractResult = extractArchive(job.inputPath, tempDir);
        if (!extractResult.empty())
            return ConversionResult::err("Extraction failed: " + extractResult);

        if (job.onProgress) job.onProgress(0.5f, "Repacking...");

        // Step 2: repack extracted files into output format
        auto packResult = packArchive(tempDir, job.outputPath, job.outputFormat.ext);
        if (!packResult.empty())
            return ConversionResult::err("Packing failed: " + packResult);

        if (job.onProgress) job.onProgress(0.9f, "Cleaning up...");

        // Step 3: clean up temp dir
        fs::remove_all(tempDir);

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result        = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes  = fs::file_size(job.inputPath);
        result.outputBytes = fs::file_size(job.outputPath);
        return result;
    }

private:
    // Returns empty string on success, error message on failure
    static std::string extractArchive(const fs::path& src, const fs::path& destDir) {
        struct archive* a = archive_read_new();
        archive_read_support_format_all(a);
        archive_read_support_filter_all(a);

        if (archive_read_open_filename(a, src.string().c_str(), 10240) != ARCHIVE_OK) {
            std::string err = archive_error_string(a);
            archive_read_free(a);
            return err;
        }

        struct archive* ext = archive_write_disk_new();
        archive_write_disk_set_options(ext,
            ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM | ARCHIVE_EXTRACT_ACL | ARCHIVE_EXTRACT_FFLAGS);
        archive_write_disk_set_standard_lookup(ext);

        struct archive_entry* entry;
        while (archive_read_next_header(a, &entry) == ARCHIVE_OK) {
            // Sanitize entry path to prevent zip-slip (path traversal) attacks.
            fs::path clean;
            for (auto& component : fs::path(archive_entry_pathname(entry))) {
                std::string s = component.string();
                if (s == ".." || s == "/" || s == "\\") continue;
                clean /= component;
            }
            if (clean.empty()) continue;

            fs::path fullPath    = destDir / clean;
            fs::path resolved    = fs::weakly_canonical(fullPath);
            fs::path resolvedDir = fs::weakly_canonical(destDir);
            auto [mEnd, rEnd] = std::mismatch(
                resolvedDir.begin(), resolvedDir.end(),
                resolved.begin(), resolved.end());
            if (mEnd != resolvedDir.end()) continue; // escapes destDir — skip

            archive_entry_set_pathname(entry, fullPath.string().c_str());

            if (archive_write_header(ext, entry) != ARCHIVE_OK) {
                std::string err = archive_error_string(ext);
                archive_read_free(a);
                archive_write_free(ext);
                return err;
            }

            copyData(a, ext);
        }

        archive_read_free(a);
        archive_write_free(ext);
        return "";
    }

    static std::string packArchive(const fs::path& srcDir, const fs::path& dest, const std::string& fmt) {
        struct archive* a = archive_write_new();

        // Set format and filter based on output extension
        if (fmt == "zip") {
            archive_write_set_format_zip(a);
        } else if (fmt == "tar") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_none(a);
        } else if (fmt == "gz") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_gzip(a);
        } else if (fmt == "bz2") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_bzip2(a);
        } else if (fmt == "xz") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_xz(a);
        } else if (fmt == "zst") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_zstd(a);
        } else if (fmt == "7z") {
            archive_write_set_format_7zip(a);
        } else if (fmt == "tgz") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_gzip(a);
        } else if (fmt == "tbz2") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_bzip2(a);
        } else if (fmt == "txz") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_xz(a);
        } else if (fmt == "lz4") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_lz4(a);
        } else if (fmt == "lzma") {
            archive_write_set_format_pax_restricted(a);
            archive_write_add_filter_lzma(a);
        } else if (fmt == "rar") {
            archive_write_free(a);
            return "RAR is a proprietary format — writing .rar files is not supported. "
                "Try converting to .zip or .7z instead.";
        } else {
            archive_write_free(a);
            return "Unsupported archive output format: " + fmt;
        }

        if (archive_write_open_filename(a, dest.string().c_str()) != ARCHIVE_OK) {
            std::string err = archive_error_string(a);
            archive_write_free(a);
            return err;
        }

        // Walk srcDir and add every file
        std::vector<char> buf(8192);
        for (auto& dirEntry : fs::recursive_directory_iterator(srcDir)) {
            if (!dirEntry.is_regular_file()) continue;

            fs::path filePath = dirEntry.path();
            fs::path relPath  = fs::relative(filePath, srcDir);

            struct archive_entry* entry = archive_entry_new();
            archive_entry_set_pathname(entry, relPath.string().c_str());
            archive_entry_set_size(entry, fs::file_size(filePath));
            archive_entry_set_filetype(entry, AE_IFREG);
            archive_entry_set_perm(entry, 0644);

            archive_write_header(a, entry);

            // Write file contents
            std::ifstream f(filePath.string(), std::ios::binary);
            while ((f.read(buf.data(), buf.size()), f.gcount() > 0))
                archive_write_data(a, buf.data(), f.gcount());

            archive_entry_free(entry);
        }

        archive_write_close(a);
        archive_write_free(a);
        return "";
    }

    static void copyData(struct archive* ar, struct archive* aw) {
        const void* buff;
        size_t size;
        la_int64_t offset;
        while (archive_read_data_block(ar, &buff, &size, &offset) == ARCHIVE_OK)
            archive_write_data_block(aw, buff, size, offset);
    }
};

} // namespace converter