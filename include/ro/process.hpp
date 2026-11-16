#pragma once
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>

#include <cstdint>
#include <optional>
#include <string>
#include <vector>

namespace ro::proc {

struct Entry {
    std::uint32_t pid = 0;
    std::wstring name;  // e.g. L"RustClient.exe"
};

// Case-insensitive match on the image name; "RustClient" and "RustClient.exe"
// both work.
std::vector<Entry> find(std::wstring_view name);
std::optional<Entry> find_first(std::wstring_view name);
std::vector<Entry> find_many(const std::vector<std::wstring>& names);
bool is_running(std::wstring_view name);

bool set_priority(std::uint32_t pid, DWORD priority_class);
std::optional<DWORD> get_priority(std::uint32_t pid);
bool set_affinity(std::uint32_t pid, DWORD_PTR mask);
std::optional<DWORD_PTR> get_affinity(std::uint32_t pid);
std::optional<std::wstring> image_path(std::uint32_t pid);
// Current working set in bytes, if the process is readable.
std::optional<std::uint64_t> working_set(std::uint32_t pid);

// Waits (bounded) until a process with the given image name appears.
std::optional<Entry> wait_for(std::wstring_view name, int timeout_ms, int poll_ms = 250);

}  // namespace ro::proc
