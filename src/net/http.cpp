#include "ro/http.hpp"

#include <windows.h>
#include <winhttp.h>

#include <cctype>
#include <cstdio>
#include <vector>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"
#include "ro/win32.hpp"

namespace ro::net {

namespace {

struct InternetCloser {
    void operator()(void* h) const noexcept {
        if (h) ::WinHttpCloseHandle(static_cast<HINTERNET>(h));
    }
};
using unique_inet = std::unique_ptr<void, InternetCloser>;

// Reads a response header as UTF-16 → UTF-8. Works for any header name.
std::string query_header(HINTERNET request, const wchar_t* name) {
    DWORD size = 0;
    ::WinHttpQueryHeaders(request, WINHTTP_QUERY_CUSTOM, name, nullptr, &size, WINHTTP_NO_HEADER_INDEX);
    if (size == 0) return {};
    std::wstring buffer(size / sizeof(wchar_t) + 1, L'\0');
    if (!::WinHttpQueryHeaders(request, WINHTTP_QUERY_CUSTOM, name, buffer.data(), &size,
                               WINHTTP_NO_HEADER_INDEX)) {
        return {};
    }
    while (!buffer.empty() && buffer.back() == L'\0') buffer.pop_back();
    return str::narrow(buffer);
}

std::uint32_t query_status(HINTERNET request) {
    DWORD status = 0;
    DWORD size = sizeof(status);
    if (!::WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                               WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX)) {
        return 0;
    }
    return status;
}

std::wstring resolve_location(const std::wstring& base, const std::string& location) {
    const std::wstring loc = str::widen(location);
    if (str::starts_with(str::to_lower(loc), L"http://") || str::starts_with(str::to_lower(loc), L"https://")) {
        return loc;
    }
    URL_COMPONENTS uc{};
    uc.dwStructSize = sizeof(uc);
    wchar_t scheme[16]{};
    wchar_t host[256]{};
    uc.lpszScheme = scheme;
    uc.dwSchemeLength = static_cast<DWORD>(std::size(scheme));
    uc.lpszHostName = host;
    uc.dwHostNameLength = static_cast<DWORD>(std::size(host));
    if (!::WinHttpCrackUrl(base.c_str(), static_cast<DWORD>(base.size()), 0, &uc)) return loc;
    const std::wstring prefix = std::wstring(scheme, uc.dwSchemeLength) + L"://" +
                                std::wstring(host, uc.dwHostNameLength) +
                                (uc.nPort == 443 || uc.nPort == 80 ? L"" : L":" + std::to_wstring(uc.nPort));
    if (!loc.empty() && loc[0] == L'/') return prefix + loc;
    return prefix + L"/" + loc;
}

struct UrlParts {
    std::wstring host;
    std::wstring target;
    std::uint16_t port = 443;
    bool secure = true;
    bool valid = false;
};

UrlParts split_url(const std::wstring& url) {
    UrlParts p;
    URL_COMPONENTS uc{};
    uc.dwStructSize = sizeof(uc);
    wchar_t host[256]{};
    wchar_t path[8192]{};
    wchar_t extra[2048]{};
    uc.lpszHostName = host;
    uc.dwHostNameLength = static_cast<DWORD>(std::size(host));
    uc.lpszUrlPath = path;
    uc.dwUrlPathLength = static_cast<DWORD>(std::size(path));
    uc.lpszExtraInfo = extra;
    uc.dwExtraInfoLength = static_cast<DWORD>(std::size(extra));
    if (!::WinHttpCrackUrl(url.c_str(), static_cast<DWORD>(url.size()), 0, &uc)) return p;
    p.host.assign(host, uc.dwHostNameLength);
    p.target.assign(path, uc.dwUrlPathLength);
    if (p.target.empty()) p.target = L"/";
    if (uc.dwExtraInfoLength) p.target.append(extra, uc.dwExtraInfoLength);
    p.port = uc.nPort;
    p.secure = uc.nScheme == INTERNET_SCHEME_HTTPS;
    p.valid = !p.host.empty();
    return p;
}

}  // namespace

bool is_https(const std::wstring& url) {
    return str::starts_with(str::to_lower(url), L"https://");
}

std::wstring url_encode(const std::string& text) {
    static const char* hex = "0123456789ABCDEF";
    std::wstring out;
    for (unsigned char c : text) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out.push_back(static_cast<wchar_t>(c));
        } else {
            out.push_back(L'%');
            out.push_back(static_cast<wchar_t>(hex[c >> 4]));
            out.push_back(static_cast<wchar_t>(hex[c & 0xF]));
        }
    }
    return out;
}

Client::Client() {
    const std::wstring agent = L"RustOptimizer/" + str::widen(RO_VERSION);
    HINTERNET session = ::WinHttpOpen(agent.c_str(), WINHTTP_ACCESS_TYPE_AUTOMATIC_PROXY, WINHTTP_NO_PROXY_NAME,
                                      WINHTTP_NO_PROXY_BYPASS, 0);
    if (!session) {
        log::warn("http: WinHttpOpen failed: " + win::last_error_text());
    }
    session_ = session;
}

Client::~Client() {
    if (session_) ::WinHttpCloseHandle(static_cast<HINTERNET>(session_));
}

Response Client::request(const Request& req) const {
    Response resp;
    if (!session_) {
        resp.error = "HTTP-сессия не создана";
        return resp;
    }

    std::wstring url = req.url;
    for (int hop = 0; hop < 6; ++hop) {
        const UrlParts parts = split_url(url);
        if (!parts.valid) {
            resp.error = "некорректный URL";
            return resp;
        }
        if (!parts.secure) {
            resp.error = "разрешены только HTTPS-запросы";
            return resp;
        }
        unique_inet connect(::WinHttpConnect(static_cast<HINTERNET>(session_), parts.host.c_str(), parts.port, 0));
        if (!connect) {
            resp.error = "WinHttpConnect: " + win::last_error_text();
            return resp;
        }
        unique_inet handle(::WinHttpOpenRequest(connect.get(), req.method.c_str(), parts.target.c_str(), nullptr,
                                                WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                                parts.secure ? WINHTTP_FLAG_SECURE : 0));
        if (!handle) {
            resp.error = "WinHttpOpenRequest: " + win::last_error_text();
            return resp;
        }
        ::WinHttpSetTimeouts(handle.get(), req.timeout_ms, req.timeout_ms, req.timeout_ms, req.timeout_ms);

        std::wstring headers;
        for (const auto& [k, v] : req.headers) headers += k + L": " + v + L"\r\n";
        if (!headers.empty()) headers.resize(headers.size() - 2);

        void* body = req.body.empty() ? WINHTTP_NO_REQUEST_DATA : const_cast<char*>(req.body.data());
        const DWORD body_len = static_cast<DWORD>(req.body.size());
        if (!::WinHttpSendRequest(handle.get(),
                                  headers.empty() ? WINHTTP_NO_ADDITIONAL_HEADERS : headers.c_str(),
                                  headers.empty() ? 0 : static_cast<DWORD>(headers.size()), body, body_len,
                                  body_len, 0)) {
            resp.error = "WinHttpSendRequest: " + win::last_error_text();
            return resp;
        }
        if (!::WinHttpReceiveResponse(handle.get(), nullptr)) {
            resp.error = "WinHttpReceiveResponse: " + win::last_error_text();
            return resp;
        }
        resp.status = static_cast<int>(query_status(handle.get()));
        if ((resp.status == 301 || resp.status == 302 || resp.status == 303 || resp.status == 307 ||
             resp.status == 308)) {
            const std::string location = query_header(handle.get(), L"Location");
            if (location.empty()) {
                resp.error = "редирект без Location";
                return resp;
            }
            url = resolve_location(url, location);
            continue;
        }

        DWORD available = 0;
        for (;;) {
            if (!::WinHttpQueryDataAvailable(handle.get(), &available)) {
                resp.error = "WinHttpQueryDataAvailable: " + win::last_error_text();
                return resp;
            }
            if (available == 0) break;
            std::string chunk(available, '\0');
            DWORD read = 0;
            if (!::WinHttpReadData(handle.get(), chunk.data(), available, &read)) {
                resp.error = "WinHttpReadData: " + win::last_error_text();
                return resp;
            }
            resp.body.append(chunk.data(), read);
            if (resp.body.size() > req.max_body_bytes) {
                resp.error = "ответ слишком большой";
                return resp;
            }
        }
        return resp;
    }
    resp.error = "слишком много редиректов";
    return resp;
}

Response Client::get(const std::wstring& url,
                     std::vector<std::pair<std::wstring, std::wstring>> headers) const {
    Request r;
    r.url = url;
    r.headers = std::move(headers);
    return request(r);
}

Response Client::post_json(const std::wstring& url, const std::string& json,
                           std::vector<std::pair<std::wstring, std::wstring>> headers) const {
    Request r;
    r.url = url;
    r.method = L"POST";
    r.body = json;
    headers.emplace_back(L"Content-Type", L"application/json");
    r.headers = std::move(headers);
    return request(r);
}

bool Client::download(const std::wstring& url, const std::filesystem::path& dest,
                      const ProgressFn& progress, std::atomic<bool>* cancel, std::string& error) const {
    if (!session_) {
        error = "HTTP-сессия не создана";
        return false;
    }
    std::wstring current = url;
    for (int hop = 0; hop < 6; ++hop) {
        const UrlParts parts = split_url(current);
        if (!parts.valid) {
            error = "некорректный URL";
            return false;
        }
        if (!parts.secure) {
            error = "скачивание разрешено только по HTTPS";
            return false;
        }
        unique_inet connect(::WinHttpConnect(static_cast<HINTERNET>(session_), parts.host.c_str(), parts.port, 0));
        if (!connect) {
            error = "WinHttpConnect: " + win::last_error_text();
            return false;
        }
        unique_inet handle(::WinHttpOpenRequest(connect.get(), L"GET", parts.target.c_str(), nullptr,
                                                WINHTTP_NO_REFERER, WINHTTP_DEFAULT_ACCEPT_TYPES,
                                                WINHTTP_FLAG_SECURE));
        if (!handle) {
            error = "WinHttpOpenRequest: " + win::last_error_text();
            return false;
        }
        ::WinHttpSetTimeouts(handle.get(), 15000, 15000, 30000, 60000);
        if (!::WinHttpSendRequest(handle.get(), WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0)) {
            error = "WinHttpSendRequest: " + win::last_error_text();
            return false;
        }
        if (!::WinHttpReceiveResponse(handle.get(), nullptr)) {
            error = "WinHttpReceiveResponse: " + win::last_error_text();
            return false;
        }
        const std::uint32_t status = query_status(handle.get());
        if (status == 301 || status == 302 || status == 303 || status == 307 || status == 308) {
            const std::string location = query_header(handle.get(), L"Location");
            if (location.empty()) {
                error = "редирект без Location";
                return false;
            }
            current = resolve_location(current, location);
            continue;
        }
        if (status < 200 || status >= 300) {
            error = str::fmt("сервер вернул HTTP %lu", status);
            return false;
        }

        std::uint64_t total = 0;
        if (const auto n = str::to_int(query_header(handle.get(), L"Content-Length"))) {
            if (*n > 0) total = static_cast<std::uint64_t>(*n);
        }

        fsx::ensure_dir(dest.parent_path());
        FILE* file = _wfopen(dest.wstring().c_str(), L"wb");
        if (!file) {
            error = "не удалось создать файл " + str::narrow(dest.wstring());
            return false;
        }
        std::uint64_t done = 0;
        bool ok = true;
        for (;;) {
            if (cancel && cancel->load()) {
                error = "загрузка отменена";
                ok = false;
                break;
            }
            DWORD available = 0;
            if (!::WinHttpQueryDataAvailable(handle.get(), &available)) {
                error = "WinHttpQueryDataAvailable: " + win::last_error_text();
                ok = false;
                break;
            }
            if (available == 0) break;
            std::vector<char> buffer(available);
            DWORD read = 0;
            if (!::WinHttpReadData(handle.get(), buffer.data(), available, &read)) {
                error = "WinHttpReadData: " + win::last_error_text();
                ok = false;
                break;
            }
            if (std::fwrite(buffer.data(), 1, read, file) != read) {
                error = "ошибка записи файла";
                ok = false;
                break;
            }
            done += read;
            if (progress) progress(done, total);
        }
        std::fflush(file);
        std::fclose(file);
        if (!ok) {
            fsx::remove_file(dest);
            return false;
        }
        if (total > 0 && done != total) {
            error = "загрузка неполная";
            fsx::remove_file(dest);
            return false;
        }
        return true;
    }
    error = "слишком много редиректов";
    return false;
}

}  // namespace ro::net
