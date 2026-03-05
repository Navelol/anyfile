#pragma once

#include "Types.h"
#include "Subprocess.h"
#include <chrono>

namespace converter {

class MediaConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        ConversionResult result;
        const std::string& outExt = job.outputFormat.ext;

        if (outExt == "gif") {
            result = convertGif(job);
        } else if (job.twoPass && job.videoBitrate) {
            // VBR 2-pass encode
            result = convertTwoPass(job);
        } else {
            auto args = (outExt == "ico") ? buildIcoArgs(job) : buildFFmpegArgs(job);
            int rc = Process::runCancellable("ffmpeg", args, job.cancelFlag);
            if (rc == -2) return ConversionResult::cancelled();
            if (rc != 0)  return ConversionResult::err("FFmpeg conversion failed");
            result = ConversionResult::ok(job.outputPath);
        }

        if (!result.success) return result;

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        result.durationSeconds = std::chrono::duration<double>(end - start).count();
        result.inputBytes      = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);

        return result;
    }

    // VBR 2-pass: pass 1 analysis → pass 2 encode
    static ConversionResult convertTwoPass(const ConversionJob& job) {
        auto args1 = buildFFmpegArgs(job);
        // Pass 1: output to null, write stats
        // Replace output path with null device
        args1.pop_back(); // remove output path
#ifdef _WIN32
        args1.push_back("-f"); args1.push_back("null"); args1.push_back("NUL");
#else
        args1.push_back("-f"); args1.push_back("null"); args1.push_back("/dev/null");
#endif
        // Insert pass 1 flag before output
        args1.push_back("-pass"); args1.push_back("1");

        if (job.onProgress) job.onProgress(0.15f, "Pass 1 / 2...");
        int rc1 = Process::runCancellable("ffmpeg", args1, job.cancelFlag);
        if (rc1 == -2) return ConversionResult::cancelled();
        if (rc1 != 0)  return ConversionResult::err("FFmpeg 2-pass (pass 1) failed");

        if (job.cancelFlag && job.cancelFlag->load())
            return ConversionResult::cancelled();

        // Pass 2: actual encode
        auto args2 = buildFFmpegArgs(job);
        args2.push_back("-pass"); args2.push_back("2");

        if (job.onProgress) job.onProgress(0.55f, "Pass 2 / 2...");
        int rc2 = Process::runCancellable("ffmpeg", args2, job.cancelFlag);
        if (rc2 == -2) return ConversionResult::cancelled();
        if (rc2 != 0)  return ConversionResult::err("FFmpeg 2-pass (pass 2) failed");

        return ConversionResult::ok(job.outputPath);
    }

private:
    struct Defaults {
        std::string videoCodec;
        std::string audioCodec;
        std::string pixelFormat;
        int         crf = -1;
        std::string audioBitrate;  // default audio bitrate (empty = codec default)
    };

    static Defaults defaultsFor(const std::string& outExt) {
        // CRF 16: visually transparent for H.264 (lossless ~0-10, transparent ~16-18, normal 23)
        // CRF 24: high quality for VP9 (scale 0-63, 24 = excellent)
        if (outExt == "mp4" || outExt == "m4v")
            return { "libx264", "aac", "yuv420p", 16, "320k" };
        if (outExt == "mkv")
            return { "libx264", "aac", "yuv420p", 16, "320k" };
        if (outExt == "webm")
            return { "libvpx-vp9", "libopus", "yuv420p", 24, "192k" };
        if (outExt == "mov")
            return { "libx264", "aac", "yuv420p", 16, "320k" };
        if (outExt == "avi")
            return { "mpeg4", "libmp3lame", "yuv420p", -1, "320k" };
        if (outExt == "mp3")  return { "", "libmp3lame", "", -1, "320k" };
        if (outExt == "aac")  return { "", "aac",        "", -1, "320k" };
        if (outExt == "ogg")  return { "", "libvorbis",  "", -1, "" };    // VBR-only
        if (outExt == "opus") return { "", "libopus",    "", -1, "192k" };
        if (outExt == "flac") return { "", "flac",       "", -1, "" };    // lossless
        if (outExt == "wav")  return { "", "pcm_s16le",  "", -1, "" };    // lossless
        if (outExt == "m4a")  return { "", "aac",        "", -1, "320k" };
        return { "", "", "", -1, "" };
    }

    static std::vector<std::string> buildIcoArgs(const ConversionJob& job) {
        return {
            "-y", "-i", job.inputPath.string(),
            "-filter_complex",
            "[0:v]scale=256:256:flags=lanczos[s256]"
            ";[0:v]scale=48:48:flags=lanczos[s48]"
            ";[0:v]scale=32:32:flags=lanczos[s32]"
            ";[0:v]scale=16:16:flags=lanczos[s16]",
            "-map", "[s256]", "-map", "[s48]", "-map", "[s32]", "-map", "[s16]",
            job.outputPath.string()
        };
    }

    static ConversionResult convertGif(const ConversionJob& job) {
        std::string scaleFilter;
        if (job.resolution) {
            auto x = job.resolution->find('x');
            if (x != std::string::npos)
                scaleFilter = "scale=" + job.resolution->substr(0, x)
                            + ":" + job.resolution->substr(x + 1) + ",";
        }
        std::string fpsFilter;
        if (job.framerate) fpsFilter = "fps=" + *job.framerate + ",";
        std::string filters = fpsFilter + scaleFilter;

        fs::path palette = makeTempName("anyfile_palette_", ".png");

        // Pass 1
        int rc = Process::runCancellable("ffmpeg", {
            "-y", "-i", job.inputPath.string(),
            "-vf", filters + "palettegen",
            palette.string()
        }, job.cancelFlag);

        if (rc == -2) { fs::remove(palette); return ConversionResult::cancelled(); }
        if (rc != 0)  { fs::remove(palette); return ConversionResult::err("FFmpeg GIF palette generation failed"); }

        // Check cancel between passes
        if (job.cancelFlag && job.cancelFlag->load()) {
            fs::remove(palette);
            return ConversionResult::cancelled();
        }

        // Pass 2
        rc = Process::runCancellable("ffmpeg", {
            "-y",
            "-i", job.inputPath.string(),
            "-i", palette.string(),
            "-lavfi", filters + "paletteuse",
            job.outputPath.string()
        }, job.cancelFlag);

        fs::remove(palette);

        if (rc == -2) return ConversionResult::cancelled();
        if (rc != 0)  return ConversionResult::err("FFmpeg GIF render failed");

        return ConversionResult::ok(job.outputPath);
    }

    static std::vector<std::string> buildFFmpegArgs(const ConversionJob& job) {
        const std::string& outExt = job.outputFormat.ext;
        Defaults def = defaultsFor(outExt);

        auto resolve = [](const std::optional<std::string>& ov,
                          const std::string& d) -> std::string {
            return ov ? *ov : d;
        };

        std::string vcodec = resolve(job.videoCodec,  def.videoCodec);
        std::string acodec = resolve(job.audioCodec,  def.audioCodec);
        std::string pix    = resolve(job.pixelFormat, def.pixelFormat);
        int         crf    = job.crf ? *job.crf : def.crf;
        // Use default audio bitrate if not explicitly overridden.
        // Skip for lossless/VBR-only codecs (flac, pcm_*, libvorbis) — they don't accept -b:a.
        std::string defaultABitrate;
        if (!job.audioBitrate && !def.audioBitrate.empty()) {
            bool vbrOnlyCodec = (acodec == "flac" || acodec == "libvorbis"
                              || acodec.rfind("pcm_", 0) == 0);
            if (!vbrOnlyCodec)
                defaultABitrate = def.audioBitrate;
        }

        std::vector<std::string> args;
        args.push_back("-y");
        args.push_back("-i");
        args.push_back(job.inputPath.string());

        if (!vcodec.empty()) { args.push_back("-c:v"); args.push_back(vcodec); }
        if (!vcodec.empty() && (outExt == "mp4" || outExt == "mkv" || outExt == "mov"))
            { args.push_back("-preset"); args.push_back("slow"); }

        // AV1 via libaom defaults to cpu-used 1 which is glacially slow.
        // cpu-used 6 is the sweet spot: ~99% of max quality at a fraction of the time.
        if (vcodec == "libaom-av1") {
            args.push_back("-cpu-used"); args.push_back("6");
            args.push_back("-row-mt");   args.push_back("1");
        }
        if (!acodec.empty()) { args.push_back("-c:a"); args.push_back(acodec); }
        if (crf >= 0)        { args.push_back("-crf"); args.push_back(std::to_string(crf)); }
        if (!pix.empty())    { args.push_back("-pix_fmt"); args.push_back(pix); }

        if (job.videoBitrate) { args.push_back("-b:v"); args.push_back(*job.videoBitrate); }
        if (job.videoMaxRate) {
            args.push_back("-maxrate"); args.push_back(*job.videoMaxRate);
            // bufsize = 2× maxrate is a sensible default
            args.push_back("-bufsize"); args.push_back(*job.videoMaxRate);
        }
        // Apply audio bitrate: explicit override takes priority, then format default.
        // Skip for lossless/VBR-only codecs (flac, pcm_*, libvorbis).
        if (job.audioBitrate)            { args.push_back("-b:a"); args.push_back(*job.audioBitrate); }
        else if (!defaultABitrate.empty()) { args.push_back("-b:a"); args.push_back(defaultABitrate); }

        if (job.resolution) {
            auto x = job.resolution->find('x');
            if (x != std::string::npos) {
                args.push_back("-vf");
                args.push_back("scale=" + job.resolution->substr(0, x)
                              + ":" + job.resolution->substr(x + 1));
            }
        }
        if (job.framerate) { args.push_back("-r"); args.push_back(*job.framerate); }

        args.push_back(job.outputPath.string());
        return args;
    }
};

} // namespace converter