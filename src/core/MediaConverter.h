#pragma once

#include "Types.h"
#include <cstdlib>
#include <chrono>

namespace converter {

class MediaConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        std::string cmd = "ffmpeg -y -i \"" + job.inputPath.string() + 
                          "\" \"" + job.outputPath.string() + "\" 2>/dev/null";

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        int ret = std::system(cmd.c_str());

        if (ret != 0)
            return ConversionResult::err("FFmpeg conversion failed");

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);

        return result;
    }
};

} // namespace converter