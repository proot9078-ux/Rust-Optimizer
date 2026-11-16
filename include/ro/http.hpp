#pragma once
#include <atomic>
#include <cstdint>
#include <filesystem>
#include <functional>
#include <map>
#include <optional>
#include <string>
#include <vector>

namespace ro::net {

struct Response {
    int status = 0;
    std::string body;
    std::map<std::string, std::string> headers;
    std::string error;
    bool ok() const { return status >= 200 && status < 300 && error.empty(); }
};

using ProgressFn = std::function<void(std::uint64_t done, std::uint64_t total)>;

struct Request {
    std::wstring url;
    std::vector<std::pair<std::wstring, std::wstring>> headers;
    std::string body;                       // POST payload when method == POST
    std::wstring method = L"GET";
    int timeout_ms = 20000;
    std::uint64_t max_body_bytes = 8ull * 1024 * 1024;
};

class Client {
public:
    Client();
    ~Client();
    Client(const Client&) = delete;
    Client& operator=(const Client&) = delete;

    Response request(const Request& req) const;
    Response get(const std::wstring& url, std::vector<std::pair<std::wstring, std::wstring>> headers = {}) const;
    Response post_json(const std::wstring& url, const std::string& json,
                       std::vector<std::pair<std::wstring, std::wstring>> headers = {}) const;

    // Streams to disk. Enforces TLS certificate validation (default WinHTTP).
    bool download(const std::wstring& url, const std::filesystem::path& dest,
                  const ProgressFn& progress, std::atomic<bool>* cancel, std::string& error) const;

private:
    void* session_ = nullptr;  // HINTERNET
};

bool is_https(const std::wstring& url);
std::wstring url_encode(const std::string& text);

}  // namespace ro::net
