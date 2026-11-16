#include "ro/win32.hpp"

#include <shellapi.h>

#include <cstring>
#include <string>

#include "ro/str.hpp"

namespace ro::win {

std::wstring last_error_text_w(DWORD code) {
    if (code == 0) code = ::GetLastError();
    if (code == 0) return L"no error";
    wchar_t* buffer = nullptr;
    const DWORD n = ::FormatMessageW(
        FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, nullptr,
        code, MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT), reinterpret_cast<wchar_t*>(&buffer), 0, nullptr);
    std::wstring result;
    if (n && buffer) {
        result.assign(buffer, n);
        while (!result.empty() && (result.back() == L'\r' || result.back() == L'\n' || result.back() == L' ')) {
            result.pop_back();
        }
    } else {
        result = str::wfmt(L"unknown error %lu", code);
    }
    if (buffer) ::LocalFree(buffer);
    return str::wfmt(L"%ls (0x%08lX)", result.c_str(), code);
}

std::string last_error_text(DWORD code) { return str::narrow(last_error_text_w(code)); }

bool is_admin() {
    HANDLE token = nullptr;
    if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
    TOKEN_ELEVATION elevation{};
    DWORD size = sizeof(elevation);
    const bool ok = ::GetTokenInformation(token, TokenElevation, &elevation, size, &size) != FALSE;
    ::CloseHandle(token);
    return ok && elevation.TokenIsElevated != 0;
}

namespace {
// Minimal OSVERSIONINFO layout: declared locally so the code compiles with any
// SDK / MinGW header set without depending on winternl.h internals.
struct OsVersionInfo {
    ULONG size;
    ULONG major;
    ULONG minor;
    ULONG build;
    ULONG platform_id;
    wchar_t csd[128];
};
struct OsVersionData {
    ULONG dwOSVersionInfoSize;
    ULONG dwMajorVersion;
    ULONG dwMinorVersion;
    ULONG dwBuildNumber;
    ULONG dwPlatformId;
    wchar_t szCSDVersion[128];
};
using RtlGetVersionFn = LONG(WINAPI*)(OsVersionData*);

bool read_os_version(OsVersionInfo& out) {
    HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) return false;
    const auto fn = reinterpret_cast<RtlGetVersionFn>(
        reinterpret_cast<void*>(::GetProcAddress(ntdll, "RtlGetVersion")));
    if (!fn) return false;
    OsVersionData vi{};
    vi.dwOSVersionInfoSize = sizeof(vi);
    if (fn(&vi) != 0) return false;
    out.size = vi.dwOSVersionInfoSize;
    out.major = vi.dwMajorVersion;
    out.minor = vi.dwMinorVersion;
    out.build = vi.dwBuildNumber;
    out.platform_id = vi.dwPlatformId;
    std::wmemcpy(out.csd, vi.szCSDVersion, 128);
    return true;
}
}  // namespace

bool is_windows_11() {
    OsVersionInfo vi{};
    if (!read_os_version(vi)) return false;
    return vi.major >= 10 && vi.build >= 22000;
}

std::wstring windows_build_string() {
    OsVersionInfo vi{};
    if (!read_os_version(vi)) return L"Windows";
    return str::wfmt(L"Windows %lu.%lu (build %lu)", vi.major, vi.minor, vi.build);
}

bool relaunch_elevated(const std::wstring& extra_args) {
    wchar_t exe[MAX_PATH * 2]{};
    if (::GetModuleFileNameW(nullptr, exe, static_cast<DWORD>(std::size(exe))) == 0) return false;
    std::wstring params = extra_args;
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_NOCLOSEPROCESS;
    sei.lpVerb = L"runas";
    sei.lpFile = exe;
    sei.lpParameters = params.empty() ? nullptr : params.c_str();
    sei.nShow = SW_SHOWNORMAL;
    if (!::ShellExecuteExW(&sei)) {
        return false;
    }
    if (sei.hProcess) ::CloseHandle(sei.hProcess);
    return true;
}

bool shell_open(const std::wstring& target) {
    SHELLEXECUTEINFOW sei{};
    sei.cbSize = sizeof(sei);
    sei.fMask = SEE_MASK_FLAG_NO_UI;
    sei.lpVerb = L"open";
    sei.lpFile = target.c_str();
    sei.nShow = SW_SHOWNORMAL;
    return ::ShellExecuteExW(&sei) != FALSE;
}

std::wstring expand_env(const std::wstring& value) {
    wchar_t buffer[32768]{};
    const DWORD n = ::ExpandEnvironmentStringsW(value.c_str(), buffer, static_cast<DWORD>(std::size(buffer)));
    if (n == 0 || n > std::size(buffer)) return value;
    return std::wstring(buffer, n - 1);
}

bool set_dpi_awareness() {
    // DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 with a graceful fallback.
    HMODULE user32 = ::GetModuleHandleW(L"user32.dll");
    if (user32) {
        using SetCtxFn = BOOL(WINAPI*)(HANDLE);
        const auto fn = reinterpret_cast<SetCtxFn>(
            reinterpret_cast<void*>(::GetProcAddress(user32, "SetProcessDpiAwarenessContext")));
        if (fn && fn(reinterpret_cast<HANDLE>(-4))) return true;
    }
    ::SetProcessDPIAware();
    return true;
}

unique_hkey reg_open(HKEY root, const wchar_t* sub, REGSAM sam) {
    HKEY key = nullptr;
    const LONG rc = ::RegOpenKeyExW(root, sub, 0, sam, &key);
    if (rc != ERROR_SUCCESS) return {};
    return unique_hkey(key);
}

std::optional<std::wstring> reg_read_string(HKEY root, const wchar_t* sub, const wchar_t* name) {
    auto key = reg_open(root, sub);
    if (!key) return std::nullopt;
    DWORD type = 0;
    DWORD size = 0;
    LONG rc = ::RegQueryValueExW(key.get(), name, nullptr, &type, nullptr, &size);
    if (rc != ERROR_SUCCESS || (type != REG_SZ && type != REG_EXPAND_SZ) || size == 0) return std::nullopt;
    std::wstring value(size / sizeof(wchar_t), L'\0');
    rc = ::RegQueryValueExW(key.get(), name, nullptr, &type, reinterpret_cast<LPBYTE>(value.data()), &size);
    if (rc != ERROR_SUCCESS) return std::nullopt;
    while (!value.empty() && value.back() == L'\0') value.pop_back();
    return value;
}

std::optional<std::uint32_t> reg_read_dword(HKEY root, const wchar_t* sub, const wchar_t* name) {
    auto key = reg_open(root, sub);
    if (!key) return std::nullopt;
    DWORD type = 0;
    DWORD value = 0;
    DWORD size = sizeof(value);
    const LONG rc = ::RegQueryValueExW(key.get(), name, nullptr, &type, reinterpret_cast<LPBYTE>(&value), &size);
    if (rc != ERROR_SUCCESS || type != REG_DWORD) return std::nullopt;
    return value;
}

std::optional<std::uint64_t> reg_read_qword(HKEY root, const wchar_t* sub, const wchar_t* name) {
    auto key = reg_open(root, sub);
    if (!key) return std::nullopt;
    DWORD type = 0;
    std::uint64_t value = 0;
    DWORD size = sizeof(value);
    const LONG rc = ::RegQueryValueExW(key.get(), name, nullptr, &type, reinterpret_cast<LPBYTE>(&value), &size);
    if (rc != ERROR_SUCCESS || (type != REG_QWORD && type != REG_DWORD)) return std::nullopt;
    return value;
}

bool reg_write_string(HKEY root, const wchar_t* sub, const wchar_t* name, const std::wstring& value) {
    HKEY key = nullptr;
    const LONG rc = ::RegCreateKeyExW(root, sub, 0, nullptr, 0, KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr);
    if (rc != ERROR_SUCCESS) return false;
    unique_hkey holder(key);
    const DWORD bytes = static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t));
    return ::RegSetValueExW(key, name, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()), bytes) == ERROR_SUCCESS;
}

bool reg_write_dword(HKEY root, const wchar_t* sub, const wchar_t* name, std::uint32_t value) {
    HKEY key = nullptr;
    const LONG rc = ::RegCreateKeyExW(root, sub, 0, nullptr, 0, KEY_SET_VALUE | KEY_QUERY_VALUE, nullptr, &key, nullptr);
    if (rc != ERROR_SUCCESS) return false;
    unique_hkey holder(key);
    return ::RegSetValueExW(key, name, 0, REG_DWORD, reinterpret_cast<const BYTE*>(&value), sizeof(value)) ==
           ERROR_SUCCESS;
}

std::vector<RegValue> reg_snapshot(HKEY root, const wchar_t* sub) {
    std::vector<RegValue> out;
    auto key = reg_open(root, sub);
    if (!key) return out;
    for (DWORD index = 0;; ++index) {
        wchar_t name[16384]{};
        DWORD name_len = static_cast<DWORD>(std::size(name));
        DWORD type = 0;
        DWORD size = 0;
        LONG rc = ::RegEnumValueW(key.get(), index, name, &name_len, nullptr, &type, nullptr, &size);
        if (rc == ERROR_NO_MORE_ITEMS) break;
        if (rc != ERROR_SUCCESS) break;
        RegValue v;
        v.name.assign(name, name_len);
        v.type = type;
        v.raw.resize(size);
        if (size > 0) {
            rc = ::RegQueryValueExW(key.get(), name, nullptr, &type, v.raw.data(), &size);
            if (rc != ERROR_SUCCESS) continue;
            v.raw.resize(size);
        }
        out.push_back(std::move(v));
    }
    return out;
}

bool reg_restore(HKEY root, const wchar_t* sub, const std::vector<RegValue>& values) {
    HKEY key = nullptr;
    if (::RegCreateKeyExW(root, sub, 0, nullptr, 0, KEY_SET_VALUE, nullptr, &key, nullptr) != ERROR_SUCCESS) {
        return false;
    }
    unique_hkey holder(key);
    bool ok = true;
    for (const auto& v : values) {
        const LONG rc = ::RegSetValueExW(key, v.name.empty() ? nullptr : v.name.c_str(), 0, v.type, v.raw.data(),
                                        static_cast<DWORD>(v.raw.size()));
        if (rc != ERROR_SUCCESS) ok = false;
    }
    return ok;
}

}  // namespace ro::win

