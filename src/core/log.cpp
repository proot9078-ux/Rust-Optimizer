#include "ro/log.hpp"

#include <windows.h>

#include <algorithm>
#include <cstddef>
#include <cstdio>
#include <deque>
#include <filesystem>
#include <system_error>

#include "ro/str.hpp"

namespace ro::log {

namespace {

constexpr std::size_t kMaxRecords = 4000;
constexpr std::size_t kMaxFileBytes = 2u * 1024u * 1024u;

const char* level_tag(Level l) {
    switch (l) {
        case Level::Debug: return "DBG";
        case Level::Info: return "INF";
        case Level::Warn: return "WRN";
        case Level::Error: return "ERR";
        case Level::Success: return "OK ";
    }
    return "???";
}

std::string clock_string() {
    SYSTEMTIME st{};
    ::GetLocalTime(&st);
    return str::fmt("%02u:%02u:%02u", st.wHour, st.wMinute, st.wSecond);
}

std::string date_string() {
    SYSTEMTIME st{};
    ::GetLocalTime(&st);
    return str::fmt("%04u-%02u-%02u %02u:%02u:%02u", st.wYear, st.wMonth, st.wDay, st.wHour, st.wMinute,
                    st.wSecond);
}

}  // namespace

Logger& Logger::instance() {
    static Logger logger;
    return logger;
}

void Logger::set_log_file(const std::string& path, bool truncate_if_large) {
    std::lock_guard<std::mutex> lock(mutex_);
    if (file_) {
        std::fclose(static_cast<std::FILE*>(file_));
        file_ = nullptr;
    }
    file_path_ = path;
    if (truncate_if_large) {
        std::error_code ec;
        const auto size = std::filesystem::file_size(std::filesystem::path(str::widen(path)), ec);
        if (!ec && size > kMaxFileBytes) {
            std::filesystem::remove(std::filesystem::path(str::widen(path)), ec);
        }
    }
    if (!path.empty()) {
        const std::filesystem::path wide_path = std::filesystem::path(str::widen(path));
        std::filesystem::create_directories(wide_path.parent_path());
        // The user profile may contain non-ASCII characters (Cyrillic, CJK...),
        // so open through the wide API instead of a UTF-8 byte path.
        std::FILE* f = nullptr;
#if defined(_MSC_VER)
        _wfopen_s(&f, wide_path.c_str(), L"ab");
#else
        f = _wfopen(wide_path.c_str(), L"ab");
#endif
        file_ = f;
        file_open_ = f != nullptr;
    }
}

void Logger::add_sink(Sink* sink) {
    if (!sink) return;
    std::lock_guard<std::mutex> lock(mutex_);
    if (std::find(sinks_.begin(), sinks_.end(), sink) == sinks_.end()) sinks_.push_back(sink);
}

void Logger::remove_sink(Sink* sink) {
    std::lock_guard<std::mutex> lock(mutex_);
    sinks_.erase(std::remove(sinks_.begin(), sinks_.end(), sink), sinks_.end());
}

void Logger::write(Level level, const std::string& text) {
    Record rec;
    rec.level = level;
    rec.time = clock_string();
    rec.text = str::one_line(text);

    std::vector<Sink*> sinks;
    {
        std::lock_guard<std::mutex> lock(mutex_);
        records_.push_back(rec);
        if (records_.size() > kMaxRecords) records_.erase(records_.begin(), records_.begin() + 500);
        sinks = sinks_;
        if (file_) {
            const std::string line = date_string() + " [" + level_tag(level) + "] " + rec.text + "\n";
            std::fwrite(line.data(), 1, line.size(), static_cast<std::FILE*>(file_));
            std::fflush(static_cast<std::FILE*>(file_));
        }
    }
    if (level == Level::Debug && !::IsDebuggerPresent()) {
        // Debug records still reach the file and sinks; no extra handling.
    }
    for (Sink* s : sinks) {
        // Sinks must not throw; guard cheaply.
        try {
            s->on_log(rec);
        } catch (...) {
        }
    }
}

std::vector<Record> Logger::tail(std::size_t max) const {
    std::lock_guard<std::mutex> lock(mutex_);
    const std::size_t start = records_.size() > max ? records_.size() - max : 0;
    return std::vector<Record>(records_.begin() + static_cast<std::ptrdiff_t>(start), records_.end());
}

std::vector<Record> Logger::all() const {
    std::lock_guard<std::mutex> lock(mutex_);
    return records_;
}

void Logger::clear() {
    std::lock_guard<std::mutex> lock(mutex_);
    records_.clear();
}

void Logger::flush() {
    std::lock_guard<std::mutex> lock(mutex_);
    if (file_) std::fflush(static_cast<std::FILE*>(file_));
}

void debug(const std::string& text) { Logger::instance().write(Level::Debug, text); }
void info(const std::string& text) { Logger::instance().write(Level::Info, text); }
void warn(const std::string& text) { Logger::instance().write(Level::Warn, text); }
void error(const std::string& text) { Logger::instance().write(Level::Error, text); }
void success(const std::string& text) { Logger::instance().write(Level::Success, text); }

}  // namespace ro::log
