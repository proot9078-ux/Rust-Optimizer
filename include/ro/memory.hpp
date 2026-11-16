#pragma once
#include <cstdint>
#include <string>

namespace ro::mem {

struct Snapshot {
    std::uint64_t total_bytes = 0;
    std::uint64_t available_bytes = 0;
    std::uint64_t commit_total = 0;
    std::uint64_t commit_used = 0;
    std::uint64_t cached_bytes = 0;
    unsigned load_percent = 0;
};

Snapshot snapshot();

struct PurgeResult {
    bool ok = false;
    std::uint64_t freed_bytes = 0;
    unsigned long error = 0;
    std::wstring message;
};

// NtSetSystemInformation(SystemMemoryListInformation, MemoryPurgeStandbyList).
// Requires SeProfileSingleProcessPrivilege (i.e. an elevated process).
PurgeResult purge_standby_list();

// Trims the working set of a single process. Only touches the given PID.
PurgeResult empty_working_set(std::uint32_t pid);

// Enables a privilege in the current process token (e.g. SeDebugPrivilege).
bool enable_privilege(const wchar_t* name, bool& already_enabled);

}  // namespace ro::mem
