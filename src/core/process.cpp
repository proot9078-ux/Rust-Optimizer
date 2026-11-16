#include "ro/process.hpp"

#include <windows.h>
#include <psapi.h>
#include <tlhelp32.h>

#include <chrono>
#include <thread>

#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::proc {

namespace {

std::wstring normalise(std::wstring_view name) { return str::to_lower(name); }

bool name_matches(const std::wstring& actual_lower, std::wstring_view wanted_lower) {
    if (actual_lower == wanted_lower) return true;
    if (wanted_lower.find(L'.') == std::wstring_view::npos) {
        return actual_lower == std::wstring(wanted_lower) + L".exe";
    }
    return false;
}

}  // namespace

std::vector<Entry> find(std::wstring_view name) {
    std::vector<Entry> out;
    const std::wstring wanted = normalise(name);
    if (wanted.empty()) return out;

    HANDLE snap = ::CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (snap == INVALID_HANDLE_VALUE) {
        log::warn("process: snapshot failed: " + win::last_error_text());
        return out;
    }
    win::unique_handle snapshot(snap);

    PROCESSENTRY32W pe{};
    pe.dwSize = sizeof(pe);
    if (!::Process32FirstW(snap, &pe)) return out;
    do {
        const std::wstring actual = str::to_lower(pe.szExeFile);
        if (name_matches(actual, wanted)) {
            out.push_back(Entry{pe.th32ProcessID, pe.szExeFile});
        }
    } while (::Process32NextW(snap, &pe));
    return out;
}

std::optional<Entry> find_first(std::wstring_view name) {
    const auto all = find(name);
    if (all.empty()) return std::nullopt;
    return all.front();
}

std::vector<Entry> find_many(const std::vector<std::wstring>& names) {
    std::vector<Entry> out;
    for (const auto& n : names) {
        const auto found = find(n);
        out.insert(out.end(), found.begin(), found.end());
    }
    return out;
}

bool is_running(std::wstring_view name) { return !find(name).empty(); }

bool set_priority(std::uint32_t pid, DWORD priority_class) {
    HANDLE h = ::OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!h) {
        log::warn("process: OpenProcess failed for pid " + std::to_string(pid) + ": " + win::last_error_text());
        return false;
    }
    win::unique_handle holder(h);
    if (!::SetPriorityClass(h, priority_class)) {
        log::warn("process: SetPriorityClass failed: " + win::last_error_text());
        return false;
    }
    return true;
}

std::optional<DWORD> get_priority(std::uint32_t pid) {
    HANDLE h = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return std::nullopt;
    win::unique_handle holder(h);
    const DWORD cls = ::GetPriorityClass(h);
    if (cls == 0) return std::nullopt;
    return cls;
}

bool set_affinity(std::uint32_t pid, DWORD_PTR mask) {
    if (mask == 0) return false;
    HANDLE h = ::OpenProcess(PROCESS_SET_INFORMATION | PROCESS_QUERY_INFORMATION, FALSE, pid);
    if (!h) {
        log::warn("process: affinity open failed: " + win::last_error_text());
        return false;
    }
    win::unique_handle holder(h);
    if (!::SetProcessAffinityMask(h, mask)) {
        log::warn("process: SetProcessAffinityMask failed: " + win::last_error_text());
        return false;
    }
    return true;
}

std::optional<DWORD_PTR> get_affinity(std::uint32_t pid) {
    HANDLE h = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return std::nullopt;
    win::unique_handle holder(h);
    DWORD_PTR process_mask = 0;
    DWORD_PTR system_mask = 0;
    if (!::GetProcessAffinityMask(h, &process_mask, &system_mask)) return std::nullopt;
    return process_mask;
}

std::optional<std::wstring> image_path(std::uint32_t pid) {
    HANDLE h = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (!h) return std::nullopt;
    win::unique_handle holder(h);
    wchar_t buffer[32768]{};
    DWORD size = static_cast<DWORD>(std::size(buffer));
    if (!::QueryFullProcessImageNameW(h, 0, buffer, &size)) return std::nullopt;
    return std::wstring(buffer, size);
}

std::optional<std::uint64_t> working_set(std::uint32_t pid) {
    HANDLE h = ::OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!h) return std::nullopt;
    win::unique_handle holder(h);
    PROCESS_MEMORY_COUNTERS_EX counters{};
    if (!::GetProcessMemoryInfo(h, reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters))) {
        return std::nullopt;
    }
    return static_cast<std::uint64_t>(counters.WorkingSetSize);
}

std::optional<Entry> wait_for(std::wstring_view name, int timeout_ms, int poll_ms) {
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
    for (;;) {
        if (auto e = find_first(name)) return e;
        if (std::chrono::steady_clock::now() >= deadline) return std::nullopt;
        std::this_thread::sleep_for(std::chrono::milliseconds(poll_ms < 20 ? 20 : poll_ms));
    }
}

}  // namespace ro::proc
