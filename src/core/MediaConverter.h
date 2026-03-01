#pragma once

#include "Types.h"

extern "C" {
#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/avutil.h>
#include <libavutil/opt.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
}

#include <chrono>

namespace converter {

class MediaConverter {
public:
    static ConversionResult convert(const ConversionJob& job) {
        auto start = std::chrono::steady_clock::now();

        // Open input
        AVFormatContext* inFmt = nullptr;
        if (avformat_open_input(&inFmt, job.inputPath.string().c_str(), nullptr, nullptr) < 0)
            return ConversionResult::err("Could not open input file: " + job.inputPath.string());

        if (avformat_find_stream_info(inFmt, nullptr) < 0) {
            avformat_close_input(&inFmt);
            return ConversionResult::err("Could not read stream info");
        }

        // Find best streams
        int videoStream = av_find_best_stream(inFmt, AVMEDIA_TYPE_VIDEO, -1, -1, nullptr, 0);
        int audioStream = av_find_best_stream(inFmt, AVMEDIA_TYPE_AUDIO, -1, -1, nullptr, 0);

        if (videoStream < 0 && audioStream < 0) {
            avformat_close_input(&inFmt);
            return ConversionResult::err("No audio or video streams found");
        }

        // Allocate output context
        AVFormatContext* outFmt = nullptr;
        if (avformat_alloc_output_context2(&outFmt, nullptr, nullptr,
                job.outputPath.string().c_str()) < 0) {
            avformat_close_input(&inFmt);
            return ConversionResult::err("Could not create output context for: " + job.outputPath.string());
        }

        // Report progress
        if (job.onProgress) job.onProgress(0.05f, "Initializing...");

        // Copy streams
        for (unsigned i = 0; i < inFmt->nb_streams; i++) {
            AVStream* inStream  = inFmt->streams[i];
            AVStream* outStream = avformat_new_stream(outFmt, nullptr);
            if (!outStream) {
                avformat_close_input(&inFmt);
                avformat_free_context(outFmt);
                return ConversionResult::err("Failed to allocate output stream");
            }
            avcodec_parameters_copy(outStream->codecpar, inStream->codecpar);
            outStream->codecpar->codec_tag = 0;
        }

        // Open output file
        if (!(outFmt->oformat->flags & AVFMT_NOFILE)) {
            if (avio_open(&outFmt->pb, job.outputPath.string().c_str(), AVIO_FLAG_WRITE) < 0) {
                avformat_close_input(&inFmt);
                avformat_free_context(outFmt);
                return ConversionResult::err("Could not open output file for writing");
            }
        }

        // Write header
        if (avformat_write_header(outFmt, nullptr) < 0) {
            avformat_close_input(&inFmt);
            avformat_free_context(outFmt);
            return ConversionResult::err("Failed to write output header");
        }

        if (job.onProgress) job.onProgress(0.1f, "Converting...");

        // Mux packets
        AVPacket* pkt = av_packet_alloc();
        int64_t totalDuration = inFmt->duration > 0 ? inFmt->duration : 1;
        int64_t pts = 0;

        while (av_read_frame(inFmt, pkt) >= 0) {
            AVStream* inStream  = inFmt->streams[pkt->stream_index];
            AVStream* outStream = outFmt->streams[pkt->stream_index];

            // Rescale timestamps
            av_packet_rescale_ts(pkt, inStream->time_base, outStream->time_base);
            pkt->pos = -1;

            // Track progress from PTS
            if (pkt->pts != AV_NOPTS_VALUE) pts = pkt->pts;

            if (av_interleaved_write_frame(outFmt, pkt) < 0) break;

            av_packet_unref(pkt);

            // Report progress
            if (job.onProgress && totalDuration > 0) {
                double streamSecs = pts * av_q2d(inFmt->streams[pkt->stream_index]->time_base);
                double totalSecs  = (double)totalDuration / AV_TIME_BASE;
                float  progress   = 0.1f + 0.85f * (float)(streamSecs / totalSecs);
                job.onProgress(std::min(progress, 0.95f), "Converting...");
            }
        }

        av_packet_free(&pkt);
        av_write_trailer(outFmt);

        // Cleanup
        avformat_close_input(&inFmt);
        if (!(outFmt->oformat->flags & AVFMT_NOFILE))
            avio_closep(&outFmt->pb);
        avformat_free_context(outFmt);

        if (job.onProgress) job.onProgress(1.0f, "Done");

        auto end = std::chrono::steady_clock::now();
        double secs = std::chrono::duration<double>(end - start).count();

        auto result       = ConversionResult::ok(job.outputPath, secs);
        result.inputBytes = fs::file_size(job.inputPath);
        if (fs::exists(job.outputPath))
            result.outputBytes = fs::file_size(job.outputPath);

        return result;
    }
};

} // namespace converter
