#include "whisper.h"
#include "common-whisper.h"
#include "json.hpp"
#include <chrono>
#include <filesystem>
#include <iostream>
#include <memory>
#include <string>
#include <thread>
#include <vector>

using json = nlohmann::json;
using Clock = std::chrono::steady_clock;
static double milliseconds(Clock::time_point start) {
    return std::chrono::duration<double, std::milli>(Clock::now() - start).count();
}
static void reply(const json & value) { std::cout << value.dump() << '\n' << std::flush; }

int main(int argc, char ** argv) {
    if (argc != 3 || std::string(argv[1]) != "--model") return 2;
    const auto start = Clock::now();
    auto context_params = whisper_context_default_params();
    std::unique_ptr<whisper_context, decltype(&whisper_free)> context(
        whisper_init_from_file_with_params(argv[2], context_params), whisper_free);
    if (!context) { reply({{"type", "error"}, {"message", "Model could not be loaded"}}); return 3; }
    reply({{"type", "ready"}, {"load_ms", milliseconds(start)}});
    std::string line;
    while (true) {
        line.clear();
        bool oversized = false;
        char ch;
        while (std::cin.get(ch) && ch != '\n') {
            if (line.size() < 16384) line.push_back(ch);
            else oversized = true;
        }
        if (!std::cin && line.empty()) break;
        std::string id;
        try {
            if (oversized) throw std::runtime_error("Request too large");
            const auto request = json::parse(line);
            id = request.at("id").get<std::string>();
            const auto audio = request.at("audio").get<std::string>();
            const auto language = request.value("language", std::string("en"));
            const auto prompt = request.value("prompt", std::string());
            if (id.empty() || id.size() > 128 || audio.size() > 4096 || prompt.size() > 4096 ||
                (language != "en" && language != "zh" && language != "auto"))
                throw std::runtime_error("Invalid request");
            std::error_code error;
            const auto size = std::filesystem::file_size(audio, error);
            if (error || size > 5 * 1024 * 1024) throw std::runtime_error("Invalid audio file");
            std::vector<float> samples;
            std::vector<std::vector<float>> channels;
            if (!read_audio_data(audio, samples, channels, false) || samples.empty() || samples.size() > 16000 * 126)
                throw std::runtime_error("Invalid audio format or duration");
            const auto inference_start = Clock::now();
            auto params = whisper_full_default_params(WHISPER_SAMPLING_BEAM_SEARCH);
            params.n_threads = std::min(4u, std::max(1u, std::thread::hardware_concurrency()));
            params.print_realtime = false; params.print_progress = false;
            params.print_timestamps = false; params.no_timestamps = true;
            params.no_context = true; // Never carry prior dictation into the next request.
            params.language = language.c_str();
            params.detect_language = false; // Auto language still transcribes, rather than detection-only.
            params.initial_prompt = prompt.c_str();
            params.no_speech_thold = 0.6f;
            params.beam_search.beam_size = 5;
            params.greedy.best_of = 5;
            if (whisper_full(context.get(), params, samples.data(), static_cast<int>(samples.size())) != 0)
                throw std::runtime_error("Transcription failed");
            std::string text;
            for (int i = 0; i < whisper_full_n_segments(context.get()); ++i)
                text += whisper_full_get_segment_text(context.get(), i);
            reply({{"type", "result"}, {"id", id}, {"text", text}, {"inference_ms", milliseconds(inference_start)}});
        } catch (const std::exception &) {
            // Do not echo dictated text, file paths or parser input into diagnostics.
            reply({{"type", "error"}, {"id", id.size() <= 128 ? id : ""}, {"message", "Invalid audio/request or transcription failed"}});
        }
    }
    return 0;
}
