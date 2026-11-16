#include "ro/memory.hpp"

#include <windows.h>
#include <psapi.h>

#include "ro/log.hpp"
#include "ro/process.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::mem {

namespace {

// Documented-in-practice NTAPI used by RAMMap and the Windows SDK samples.
// SYSTEM_MEMORY_LIST_INFORMATION.Command values (from ntifs/ntddk):
// 1 = purge working sets, 2 = purge standby list, 3 = purge low priority
// standby list, 4 = purge all.
constexpr int kSystemMemoryListInformation = 80;
constexpr int kMemoryPurgeStandbyList = 2;

using NtSetSystemInformationFn = LONG(NTAPI*)(INT, PVOID, ULONG);

}  // namespace

Snapshot snapshot() {
    Snapshot s;
    MEMORYSTATUSEX ms{};
    ms.dwLength = sizeof(ms);
    if (::GlobalMemoryStatusEx(&ms)) {
        s.total_bytes = ms.ullTotalPhys;
        s.available_bytes = ms.ullAvailPhys;
        s.commit_total = ms.ullTotalPageFile;
        s.commit_used = ms.ullTotalPageFile - ms.ullAvailPageFile;
        s.load_percent = ms.dwMemoryLoad;
    }
    PERFORMANCE_INFORMATION pi{};
    pi.cb = sizeof(pi);
    if (::GetPerformanceInfo(&pi, sizeof(pi))) {
        s.cached_bytes = static_cast<std::uint64_t>(pi.SystemCache) * pi.PageSize;
    }
    return s;
}

bool enable_privilege(const wchar_t* name, bool& already_enabled) {
    already_enabled = false;
    HANDLE token = nullptr;
    if (!::OpenProcessToken(::GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &token)) {
        log::warn("privilege: OpenProcessToken failed: " + win::last_error_text());
        return false;
    }
    win::unique_handle holder(token);

    LUID luid{};
    if (!::LookupPrivilegeValueW(nullptr, name, &luid)) return false;

    TOKEN_PRIVILEGES tp{};
    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;
    ::SetLastError(ERROR_SUCCESS);
    if (!::AdjustTokenPrivileges(token, FALSE, &tp, sizeof(tp), nullptr, nullptr)) return false;
    const DWORD err = ::GetLastError();
    if (err == ERROR_NOT_ALL_ASSIGNED) {
        log::warn("privilege: not held by this account: " + str::narrow(name));
        return false;
    }
    already_enabled = true;
    return true;
}

PurgeResult purge_standby_list() {
    PurgeResult r;
    if (!win::is_admin()) {
        r.message = L"Нужны права администратора";
        r.error = ERROR_ACCESS_DENIED;
        return r;
    }
    bool enabled = false;
    if (!enable_privilege(L"SeProfileSingleProcessPrivilege", enabled)) {
        r.message = L"Не удалось включить SeProfileSingleProcessPrivilege";
        r.error = ::GetLastError();
        return r;
    }
    HMODULE ntdll = ::GetModuleHandleW(L"ntdll.dll");
    if (!ntdll) {
        r.message = L"ntdll.dll не загружен";
        return r;
    }
    const auto nt_set = reinterpret_cast<NtSetSystemInformationFn>(
        reinterpret_cast<void*>(::GetProcAddress(ntdll, "NtSetSystemInformation")));
    if (!nt_set) {
        r.message = L"NtSetSystemInformation недоступен";
        return r;
    }

    const Snapshot before = snapshot();
    int command = kMemoryPurgeStandbyList;
    const LONG status = nt_set(kSystemMemoryListInformation, &command, sizeof(command));
    if (status != 0) {
        r.error = static_cast<unsigned long>(status);
        r.message = str::wfmt(L"NtSetSystemInformation вернул 0x%08lX", static_cast<unsigned long>(status));
        log::warn("memory: standby purge failed: " + str::narrow(r.message));
        return r;
    }
    const Snapshot after = snapshot();
    r.ok = true;
    if (after.available_bytes > before.available_bytes) {
        r.freed_bytes = after.available_bytes - before.available_bytes;
    }
    r.message = str::wfmt(L"Standby list очищен");
    log::success("memory: standby list purged, freed " + str::human_bytes(r.freed_bytes));
    return r;
}

PurgeResult empty_working_set(std::uint32_t pid) {
    PurgeResult r;
    HANDLE h = ::OpenProcess(PROCESS_SET_QUOTA | PROCESS_QUERY_INFORMATION | PROCESS_VM_READ, FALSE, pid);
    if (!h) {
        r.error = ::GetLastError();
        r.message = L"Не удалось открыть процесс";
        return r;
    }
    win::unique_handle holder(h);
    std::uint64_t wset_before = 0;
    PROCESS_MEMORY_COUNTERS_EX counters{};
    if (::GetProcessMemoryInfo(h, reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters))) {
        wset_before = counters.WorkingSetSize;
    }
    if (!::EmptyWorkingSet(h)) {
        r.error = ::GetLastError();
        r.message = L"EmptyWorkingSet не удался";
        return r;
    }
    if (::GetProcessMemoryInfo(h, reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&counters), sizeof(counters))) {
        if (wset_before > counters.WorkingSetSize) r.freed_bytes = wset_before - counters.WorkingSetSize;
    }
    r.ok = true;
    r.message = L"Рабочий набор процесса очищен";
    return r;
}

}  // namespace ro::mem
