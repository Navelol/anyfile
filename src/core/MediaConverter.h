#pragma once

#include "Types.h"
#include <cstdlib>
#include <chrono>
#include <sstream>

namespace converter {

class MediaConverter {
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

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        std::string cmd = buildFFmpegCmd(job);
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

private:
    // ── Sensible defaults per output format ──────────────────────────────────
    struct Defaults {
        std::string videoCodec;
        std::string audioCodec;
        std::string pixelFormat;
        int         crf = -1;
    };

    static Defaults defaultsFor(const std::string& outExt) {
        if (outExt == "mp4" || outExt == "m4v")
            return { "libx264", "aac", "yuv420p", 23 };
        if (outExt == "mkv")
            return { "libx264", "aac", "yuv420p", 23 };
        if (outExt == "webm")
            return { "libvpx-vp9", "libopus", "yuv420p", 31 };
        if (outExt == "mov")
            return { "libx264", "aac", "yuv420p", 23 };
        if (outExt == "avi")
            return { "mpeg4", "libmp3lame", "yuv420p", -1 };
        if (outExt == "gif")
            return { "", "", "", -1 };
        if (outExt == "mp3")  return { "", "libmp3lame", "", -1 };
        if (outExt == "aac")  return { "", "aac",        "", -1 };
        if (outExt == "ogg")  return { "", "libvorbis",  "", -1 };
        if (outExt == "opus") return { "", "libopus",    "", -1 };
        if (outExt == "flac") return { "", "flac",       "", -1 };
        if (outExt == "wav")  return { "", "pcm_s16le",  "", -1 };
        if (outExt == "m4a")  return { "", "aac",        "", -1 };
        if (outExt == "png")  return { "", "", "", -1 };
        if (outExt == "jpg" || outExt == "jpeg") return { "", "", "", -1 };
        if (outExt == "webp") return { "", "", "", -1 };
        return { "", "", "", -1 };
    }

    // ── GIF gets special treatment — two-pass palettegen ─────────────────────
    static std::string buildGifCmd(const ConversionJob& job) {
        std::string scaleFilter;
        if (job.resolution) {
            std::string res = *job.resolution;
            auto x = res.find('x');
            if (x != std::string::npos)
                scaleFilter = "scale=" + res.substr(0, x) + ":" + res.substr(x + 1) + ",";
        }

        std::string fpsFilter;
        if (job.framerate)
            fpsFilter = "fps=" + *job.framerate + ",";

        std::string filters = fpsFilter + scaleFilter;

        fs::path palette = fs::temp_directory_path() / ("everyfile_palette_" +
            std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()) + ".png");

        std::string pass1 =
            "ffmpeg -y -i \"" + job.inputPath.string() + "\""
            " -vf \"" + filters + "palettegen\""
            " \"" + palette.string() + "\" " + DEVNULL;

        std::string pass2 =
            "ffmpeg -y -i \"" + job.inputPath.string() + "\""
            " -i \"" + palette.string() + "\""
            " -lavfi \"" + filters + "paletteuse\""
            " \"" + job.outputPath.string() + "\" " + DEVNULL +
            AND_CMD + RM_CMD + "\"" + palette.string() + "\"";

        return pass1 + AND_CMD + pass2;
    }

    // ── Main command builder ──────────────────────────────────────────────────
    static std::string buildFFmpegCmd(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;

        if (outExt == "gif")
            return buildGifCmd(job);

        Defaults def = defaultsFor(outExt);

        auto resolve = [](const std::optional<std::string>& override,
                          const std::string& def) -> std::string {
            if (override) return *override;
            return def;
        };

        std::string vcodec = resolve(job.videoCodec,   def.videoCodec);
        std::string acodec = resolve(job.audioCodec,   def.audioCodec);
        std::string pix    = resolve(job.pixelFormat,  def.pixelFormat);
        int         crf    = job.crf ? *job.crf : def.crf;

        std::ostringstream cmd;
        cmd << "ffmpeg -y -i \"" << job.inputPath.string() << "\"";

        if (!vcodec.empty())  cmd << " -c:v " << vcodec;
        if (!acodec.empty())  cmd << " -c:a " << acodec;
        if (crf >= 0)         cmd << " -crf " << crf;
        if (!pix.empty())     cmd << " -pix_fmt " << pix;
        if (job.videoBitrate) cmd << " -b:v " << *job.videoBitrate;
        if (job.audioBitrate) cmd << " -b:a " << *job.audioBitrate;

        if (job.resolution) {
            std::string res = *job.resolution;
            auto x = res.find('x');
            if (x != std::string::npos)
                cmd << " -vf scale=" << res.substr(0, x) << ":" << res.substr(x + 1);
        }

        if (job.framerate)
            cmd << " -r " << *job.framerate;

        cmd << " \"" << job.outputPath.string() << "\" " << DEVNULL;

        return cmd.str();
    }
};

} // namespace converter