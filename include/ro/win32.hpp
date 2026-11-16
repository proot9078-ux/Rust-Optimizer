#pragma once
// Thin RAII layer over the Win32 handles used by the application. Every call
// that can fail is checked; failures are surfaced with GetLastError().
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstdint>
#include <memory>
#include <optional>
#include <string>
#include <type_traits>
#include <vector>

namespace ro::win {

struct HandleCloser {
    void operator()(HANDLE h) const noexcept {
        if (h != nullptr && h != INVALID_HANDLE_VALUE) ::CloseHandle(h);
    }
};
using unique_handle = std::unique_ptr<void, HandleCloser>;

struct KeyCloser {
    void operator()(HKEY k) const noexcept {
        if (k != nullptr) ::RegCloseKey(k);
    }
};
using unique_hkey = std::unique_ptr<std::remove_pointer_t<HKEY>, KeyCloser>;

std::string last_error_text(DWORD code = ::GetLastError());
std::wstring last_error_text_w(DWORD code = ::GetLastError());
bool is_admin();
bool is_windows_11();
std::wstring windows_build_string();
// Re-launches the current executable elevated; returns false if the user
// declined the UAC prompt or the launch failed.
bool relaunch_elevated(const std::wstring& extra_args);
// Shell-executes a URI / file without a console window.
bool shell_open(const std::wstring& target);
std::wstring expand_env(const std::wstring& value);
bool set_dpi_awareness();

// ---- registry -------------------------------------------------------------
unique_hkey reg_open(HKEY root, const wchar_t* sub, REGSAM sam = KEY_READ);
std::optional<std::wstring> reg_read_string(HKEY root, const wchar_t* sub, const wchar_t* name);
std::optional<std::uint32_t> reg_read_dword(HKEY root, const wchar_t* sub, const wchar_t* name);
std::optional<std::uint64_t> reg_read_qword(HKEY root, const wchar_t* sub, const wchar_t* name);
bool reg_write_string(HKEY root, const wchar_t* sub, const wchar_t* name, const std::wstring& value);
bool reg_write_dword(HKEY root, const wchar_t* sub, const wchar_t* name, std::uint32_t value);
// Snapshot of all values under a key (used for the undo journal).
struct RegValue {
    std::wstring name;
    std::uint32_t type = 0;
    std::vector<unsigned char> raw;
};
std::vector<RegValue> reg_snapshot(HKEY root, const wchar_t* sub);
bool reg_restore(HKEY root, const wchar_t* sub, const std::vector<RegValue>& values);

}  // namespace ro::win
