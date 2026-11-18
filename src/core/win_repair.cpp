#include "ro/win_repair.hpp"

#include <windows.h>

#include <cstddef>
#include <filesystem>
#include <string>
#include <vector>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::win_repair {

namespace {

constexpr DWORD kWaitMs = 30u * 60u * 1000u;  // 30 minutes per tool

std::wstring system_tool(const wchar_t* name) {
    wchar_t dir[MAX_PATH]{};
    const UINT len = ::GetSystemDirectoryW(dir, MAX_PATH);
    if (len == 0) return name;
    std::wstring path(dir, len);
    if (!path.empty() && path.back() != L'\\') path.push_back(L'\\');
    path += name;
    return path;
}

std::wstring read_tail(const std::filesystem::path& file, std::size_t max_bytes) {
    const auto text = fsx::read_text(file);
    if (!text) return {};
    std::string_view view(*text);
    if (view.size() > max_bytes) view = view.substr(view.size() - max_bytes);
    // These tools print in the OEM code page.
    const int wide_len = ::MultiByteToWideChar(CP_OEMCP, 0, view.data(), static_cast<int>(view.size()), nullptr, 0);
    if (wide_len <= 0) return {};
    std::wstring out(static_cast<std::size_t>(wide_len), L'\0');
    ::MultiByteToWideChar(CP_OEMCP, 0, view.data(), static_cast<int>(view.size()), out.data(), wide_len);
    return out;
}

Result run_tool(const wchar_t* exe_name, const std::wstring& args, const std::wstring& label) {
    Result result;
    const std::wstring exe = system_tool(exe_name);
    if (!fsx::is_regular_file(exe)) {
        result.summary = std::wstring(L"Не найден ") + exe_name;
        return result;
    }

    const auto log_file = fsx::log_dir() / (std::wstring(L"repair-") + exe_name + L".log");
    fsx::ensure_dir(log_file.parent_path());
    result.log_file = log_file.wstring();

    SECURITY_ATTRIBUTES sa{};
    sa.nLength = sizeof(sa);
    sa.bInheritHandle = TRUE;
    HANDLE out = ::CreateFileW(log_file.c_str(), GENERIC_WRITE, FILE_SHARE_READ, &sa, CREATE_ALWAYS,
                               FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) {
        result.summary = L"Не удалось создать файл журнала исправления";
        return result;
    }
    HANDLE nul = ::CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &sa, OPEN_EXISTING,
                               FILE_ATTRIBUTE_NORMAL, nullptr);

    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    si.hStdOutput = out;
    si.hStdError = out;
    si.hStdInput = nul == INVALID_HANDLE_VALUE ? nullptr : nul;

    std::wstring cmd = L"\"" + exe + L"\" " + args;
    std::vector<wchar_t> mutable_cmd(cmd.begin(), cmd.end());
    mutable_cmd.push_back(L'\0');

    PROCESS_INFORMATION pi{};
    const BOOL started = ::CreateProcessW(exe.c_str(), mutable_cmd.data(), nullptr, nullptr, TRUE,
                                          CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi);
    ::CloseHandle(out);
    if (nul != INVALID_HANDLE_VALUE) ::CloseHandle(nul);
    if (!started) {
        result.summary = std::wstring(L"Не удалось запустить ") + exe_name + L": " + win::last_error_text_w();
        return result;
    }

    result.started = true;
    log::info("repair: " + str::narrow(label) + " started");

    const DWORD wait = ::WaitForSingleObject(pi.hProcess, kWaitMs);
    if (wait == WAIT_TIMEOUT) {
        result.timed_out = true;
        ::TerminateProcess(pi.hProcess, 1);
        ::WaitForSingleObject(pi.hProcess, 5000);
    }
    DWORD code = 0;
    ::GetExitCodeProcess(pi.hProcess, &code);
    ::CloseHandle(pi.hThread);
    ::CloseHandle(pi.hProcess);
    result.exit_code = code;
    result.ok = !result.timed_out && code == 0;

    const std::wstring tail = read_tail(log_file, 8192);
    if (!tail.empty()) log::info("repair: " + str::narrow(label) + " tail:\n" + str::narrow(tail));

    if (result.timed_out) {
        result.summary = label + L": превышено время ожидания (30 мин), процесс остановлен";
    } else if (result.ok) {
        result.summary = label + L": завершено без ошибок";
    } else {
        result.summary = label + L": код " + std::to_wstring(code) + L" (подробности в журнале)";
    }
    return result;
}

}  // namespace

bool is_admin() {
    HANDLE token = nullptr;
    if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_QUERY, &token)) return false;
    TOKEN_ELEVATION elevation{};
    DWORD size = sizeof(elevation);
    const BOOL ok = ::GetTokenInformation(token, TokenElevation, &elevation, sizeof(elevation), &size);
    ::CloseHandle(token);
    return ok != FALSE && elevation.TokenIsElevated != 0;
}

Result sfc() { return run_tool(L"sfc.exe", L"/scannow", L"SFC /scannow"); }

Result dism() {
    return run_tool(L"DISM.exe", L"/Online /Cleanup-Image /RestoreHealth", L"DISM RestoreHealth");
}

FullResult run_all() {
    FullResult full;
    if (!is_admin()) {
        full.summary = L"Для SFC и DISM нужны права администратора";
        return full;
    }
    full.sfc = sfc();
    log::info("repair: " + str::narrow(full.sfc.summary));
    full.dism = dism();
    log::info("repair: " + str::narrow(full.dism.summary));
    full.summary = full.sfc.summary + L"; " + full.dism.summary;
    return full;
}

}  // namespace ro::win_repair
