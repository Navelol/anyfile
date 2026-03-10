#pragma once

#include "Types.h"
#include "Subprocess.h"
#include <chrono>
#include <unordered_set>

namespace converter {

class DocumentConverter {
private:
#ifdef _WIN32
    static constexpr const char* SOFFICE_BIN = "soffice";
#else
    static constexpr const char* SOFFICE_BIN = "libreoffice";
#endif

public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        const std::string& inExt  = job.inputFormat.ext;
        const std::string& outExt = job.outputFormat.ext;

        if (job.onProgress) job.onProgress(0.1f, "Converting document...");

        std::string error;

        if (isEbook(inExt) || isEbook(outExt))
            error = convertEbook(job);
        else
            error = convertDocument(job);

        if (!error.empty()) {
            // Propagate cancellation as a proper cancelled result
            if (error == "__cancelled__")
                return ConversionResult::cancelled();
            return ConversionResult::err(error);
        }

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result       = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);
        return result;
    }

private:
    static bool isPandocBetter(const std::string& inExt, const std::string& outExt) {
        static const std::unordered_set<std::string> pandocFormats = {
            "md", "markdown", "html", "htm"
        };
        if (outExt == "pdf") return false;
        return pandocFormats.count(inExt) || pandocFormats.count(outExt);
    }

    static bool isEbook(const std::string& ext) {
        return ext == "epub" || ext == "mobi" || ext == "azw3"
            || ext == "azw"  || ext == "fb2";
    }

    static std::string convertEbook(const ConversionJob& job) {
        int rc = Process::runCancellable("ebook-convert", {
            job.inputPath.string(),
            job.outputPath.string()
        }, job.cancelFlag);
        if (rc == -2) return "__cancelled__";
        if (rc != 0)  return "Calibre ebook-convert failed";
        return "";
    }

    static std::string libreOfficeFilter(const std::string& ext) {
        if (ext == "pdf")  return "pdf";
        if (ext == "docx") return "docx";
        if (ext == "doc")  return "doc";
        if (ext == "odt")  return "odt";
        if (ext == "rtf")  return "rtf";
        if (ext == "txt")  return "txt";
        if (ext == "html") return "html";
        if (ext == "xlsx") return "xlsx";
        if (ext == "xls")  return "xls";
        if (ext == "ods")  return "ods";
        if (ext == "csv")  return "csv";
        if (ext == "pptx") return "pptx";
        if (ext == "ppt")  return "ppt";
        if (ext == "odp")  return "odp";
        return "";
    }

    static std::string convertDocument(const ConversionJob& job) {
        if (isPandocBetter(job.inputFormat.ext, job.outputFormat.ext))
            return convertWithPandoc(job);
        return convertWithLibreOffice(job);
    }

    static bool isPresentation(const std::string& ext) {
        return ext == "pptx" || ext == "ppt" || ext == "odp";
    }

    static bool isSpreadsheet(const std::string& ext) {
        return ext == "xlsx" || ext == "xls" || ext == "ods" || ext == "csv";
    }

    static std::string convertWithLibreOffice(const ConversionJob& job) {
        const std::string& inExt  = job.inputFormat.ext;
        const std::string& outExt = job.outputFormat.ext;

        fs::path tempDir = makeTempName("anyfile_doc_");
        fs::create_directories(tempDir);

        std::string filter = libreOfficeFilter(outExt);
        if (filter.empty()) {
            fs::remove_all(tempDir);
            return "Unsupported document output format: ." + outExt;
        }

        // LibreOffice requires an app-specific PDF export filter; the generic
        // "pdf" filter only works for Writer documents and will fail for
        // presentations or spreadsheets.
        if (outExt == "pdf") {
            if (isPresentation(inExt))
                filter = "pdf:impress_pdf_Export";
            else if (isSpreadsheet(inExt))
                filter = "pdf:calc_pdf_Export";
            else
                filter = "pdf:writer_pdf_Export";
        }

        int rc = Process::runCancellable(SOFFICE_BIN, {
            "--headless",
            "--convert-to", filter,
            "--outdir", tempDir.string(),
            job.inputPath.string()
        }, job.cancelFlag);

        if (rc == -2) { fs::remove_all(tempDir); return "__cancelled__"; }
        if (rc != 0)  { fs::remove_all(tempDir); return "LibreOffice conversion failed"; }

        fs::path libreOutput;
        for (auto& entry : fs::directory_iterator(tempDir)) {
            if (entry.is_regular_file()) { libreOutput = entry.path(); break; }
        }

        if (libreOutput.empty() || !fs::exists(libreOutput)) {
            fs::remove_all(tempDir);
            return "LibreOffice did not produce an output file";
        }

        fs::copy_file(libreOutput, job.outputPath, fs::copy_options::overwrite_existing);
        fs::remove_all(tempDir);
        return "";
    }

    static std::string convertWithPandoc(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;

        std::string pandocOut = pandocFormat(outExt);
        if (pandocOut.empty())
            return "Unsupported pandoc output format: ." + outExt;

        int rc = Process::runCancellable("pandoc", {
            job.inputPath.string(),
            "-o", job.outputPath.string()
        }, job.cancelFlag);

        if (rc == -2) return "__cancelled__";
        if (rc != 0)  return "Pandoc conversion failed";
        return "";
    }

    static std::string pandocFormat(const std::string& ext) {
        if (ext == "pdf")  return "pdf";
        if (ext == "docx") return "docx";
        if (ext == "odt")  return "odt";
        if (ext == "html") return "html";
        if (ext == "htm")  return "html";
        if (ext == "md")   return "markdown";
        if (ext == "rst")  return "rst";
        if (ext == "tex")  return "latex";
        if (ext == "txt")  return "plain";
        if (ext == "epub") return "epub";
        return "";
    }
};

} // namespace converter