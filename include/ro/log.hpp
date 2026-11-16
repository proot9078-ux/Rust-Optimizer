#pragma once
#include <functional>
#include <mutex>
#include <string>
#include <vector>

namespace ro::log {

enum class Level { Debug, Info, Warn, Error, Success };

struct Record {
    Level level = Level::Info;
    std::string time;   // HH:MM:SS
    std::string text;
};

class Sink {
public:
    virtual ~Sink() = default;
    virtual void on_log(const Record& r) = 0;
};

class Logger {
public:
    static Logger& instance();

    void set_log_file(const std::string& path, bool truncate_if_large = true);
    void add_sink(Sink* sink);       // thread-safe, sink must outlive the call
    void remove_sink(Sink* sink);
    void write(Level level, const std::string& text);
    std::vector<Record> tail(std::size_t max) const;
    std::vector<Record> all() const;
    void clear();
    void flush();

private:
    Logger() = default;
    mutable std::mutex mutex_;
    std::vector<Record> records_;
    std::vector<Sink*> sinks_;
    std::string file_path_;
    std::size_t file_bytes_ = 0;
    bool file_open_ = false;
    void* file_ = nullptr;  // FILE*
};

void debug(const std::string& text);
void info(const std::string& text);
void warn(const std::string& text);
void error(const std::string& text);
void success(const std::string& text);

}  // namespace ro::log
