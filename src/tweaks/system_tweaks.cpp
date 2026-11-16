#include "ro/system_tweaks.hpp"

#include <windows.h>

#include "ro/fs.hpp"
#include "ro/hardware.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::system_tweaks {

namespace {

constexpr const wchar_t* kLayers =
    L"Software\\Microsoft\\Windows NT\\CurrentVersion\\AppCompatFlags\\Layers";
constexpr const wchar_t* kGpuPrefs = L"Software\\Microsoft\\DirectX\\UserGpuPreferences";
constexpr const wchar_t* kGameConfig = L"System\\GameConfigStore";
constexpr const wchar_t* kGameBar = L"Software\\Microsoft\\GameBar";

bool run_hidden(const std::wstring& command_line, DWORD timeout_ms, std::string& error) {
    std::wstring cmd = command_line;
    STARTUPINFOW si{};
    si.cb = sizeof(si);
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;
    PROCESS_INFORMATION pi{};
    if (!::CreateProcessW(nullptr, cmd.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW, nullptr, nullptr, &si, &pi)) {
        error = "CreateProcessW: " + win::last_error_text();
        return false;
    }
    win::unique_handle process(pi.hProcess);
    win::unique_handle thread(pi.hThread);
    const DWORD wait = ::WaitForSingleObject(pi.hProcess, timeout_ms);
    if (wait != WAIT_OBJECT_0) {
        ::TerminateProcess(pi.hProcess, 1);
        error = "команда не завершилась за отведённое время";
        return false;
    }
    DWORD code = 1;
    ::GetExitCodeProcess(pi.hProcess, &code);
    if (code != 0) {
        error = str::fmt("команда вернула код %lu", code);
        return false;
    }
    return true;
}

std::wstring system32(const wchar_t* exe) {
    wchar_t dir[MAX_PATH]{};
    ::GetSystemDirectoryW(dir, MAX_PATH);
    return std::wstring(dir) + L"\\" + exe;
}

}  // namespace

bool flush_dns(std::string& error) {
    HMODULE dnsapi = ::LoadLibraryW(L"dnsapi.dll");
    if (!dnsapi) {
        error = "dnsapi.dll не загружен: " + win::last_error_text();
        return false;
    }
    using FlushFn = BOOL(WINAPI*)();
    const auto fn = reinterpret_cast<FlushFn>(reinterpret_cast<void*>(::GetProcAddress(dnsapi, "DnsFlushResolverCache")));
    if (!fn) {
        ::FreeLibrary(dnsapi);
        error = "DnsFlushResolverCache не найдена";
        return false;
    }
    const BOOL ok = fn();
    const DWORD err = ::GetLastError();
    ::FreeLibrary(dnsapi);
    if (!ok) {
        error = "DnsFlushResolverCache: " + win::last_error_text(err);
        return false;
    }
    log::success("system: DNS cache flushed");
    return true;
}

bool reset_winsock(std::string& error) {
    if (!win::is_admin()) {
        error = "требуются права администратора";
        return false;
    }
    if (!run_hidden(system32(L"netsh.exe") + L" winsock reset", 30000, error)) return false;
    log::success("system: Winsock reset (reboot required)");
    return true;
}

bool set_tcp_autotuning(bool normal, std::string& error) {
    const std::wstring level = normal ? L"normal" : L"restricted";
    return run_hidden(system32(L"netsh.exe") + L" int tcp set global autotuninglevel=" + level, 20000, error);
}

bool set_fullscreen_optimizations(const std::wstring& exe_path, bool enabled, std::string& error) {
    if (exe_path.empty()) {
        error = "путь к exe не задан";
        return false;
    }
    if (enabled) {
        // Remove the compatibility flag, restoring the Windows default.
        HKEY key = nullptr;
        if (::RegOpenKeyExW(HKEY_CURRENT_USER, kLayers, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
            win::unique_hkey holder(key);
            ::RegDeleteValueW(key, exe_path.c_str());
        }
        return true;
    }
    if (!win::reg_write_string(HKEY_CURRENT_USER, kLayers, exe_path.c_str(), L"~ DISABLEDXMAXIMIZEDWINDOWEDMODE")) {
        error = "не удалось записать AppCompatFlags: " + win::last_error_text();
        return false;
    }
    return true;
}

bool set_gpu_preference(const std::wstring& exe_path, int preference, std::string& error) {
    if (exe_path.empty()) {
        error = "путь к exe не задан";
        return false;
    }
    if (preference < 0 || preference > 2) {
        error = "недопустимое значение";
        return false;
    }
    if (preference == 0) {
        HKEY key = nullptr;
        if (::RegOpenKeyExW(HKEY_CURRENT_USER, kGpuPrefs, 0, KEY_SET_VALUE, &key) == ERROR_SUCCESS) {
            win::unique_hkey holder(key);
            ::RegDeleteValueW(key, exe_path.c_str());
        }
        return true;
    }
    const std::wstring value = str::wfmt(L"GpuPreference=%d;", preference);
    if (!win::reg_write_string(HKEY_CURRENT_USER, kGpuPrefs, exe_path.c_str(), value)) {
        error = "не удалось записать DirectX\\UserGpuPreferences: " + win::last_error_text();
        return false;
    }
    return true;
}

bool set_game_dvr(bool enabled, std::string& error) {
    const std::uint32_t value = enabled ? 1u : 0u;
    if (!win::reg_write_dword(HKEY_CURRENT_USER, kGameConfig, L"GameDVR_Enabled", value)) {
        error = "не удалось записать GameDVR_Enabled: " + win::last_error_text();
        return false;
    }
    win::reg_write_dword(HKEY_CURRENT_USER, kGameConfig, L"GameDVR_FSEBehaviorMode", enabled ? 2u : 0u);
    return true;
}

bool set_game_mode(bool enabled, std::string& error) {
    const std::uint32_t value = enabled ? 1u : 0u;
    if (!win::reg_write_dword(HKEY_CURRENT_USER, kGameBar, L"AutoGameModeEnabled", value) ||
        !win::reg_write_dword(HKEY_CURRENT_USER, kGameBar, L"AllowAutoGameMode", value)) {
        error = "не удалось записать параметры Game Mode: " + win::last_error_text();
        return false;
    }
    return true;
}

bool set_hags(bool enabled, std::string& error) { return ro::set_hags(enabled, error); }

GameDvrState query_game_dvr() {
    GameDvrState s;
    s.enabled = win::reg_read_dword(HKEY_CURRENT_USER, kGameConfig, L"GameDVR_Enabled").value_or(1) != 0;
    s.game_mode =
        win::reg_read_dword(HKEY_CURRENT_USER, kGameBar, L"AutoGameModeEnabled").value_or(1) != 0;
    s.supported = win::is_windows_11() || win::windows_build_string().find(L"build") != std::wstring::npos;
    return s;
}

bool open_config_folder(const std::wstring& path, std::string& error) {
    if (!fsx::is_directory(path)) {
        error = "папка не найдена: " + str::narrow(path);
        return false;
    }
    if (!win::shell_open(path)) {
        error = "не удалось открыть проводник";
        return false;
    }
    return true;
}

}  // namespace ro::system_tweaks
