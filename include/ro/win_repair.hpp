#pragma once
#include <string>

// Windows integrity repair through the official Microsoft tools:
//
//   sfc /scannow
//   DISM /Online /Cleanup-Image /RestoreHealth
//
// Both are started with CreateProcessW and CREATE_NO_WINDOW (never cmd.exe),
// their output is written to a log file, and the process is terminated when it
// exceeds the time budget. Nothing is downloaded and no system files are
// modified outside of what the tools themselves do.
namespace ro::win_repair {

struct Result {
    bool started = false;   // the tool could be launched
    bool ok = false;        // exit code 0
    bool timed_out = false;
    unsigned exit_code = 0;
    std::wstring summary;   // one-line human readable result
    std::wstring log_file;  // full output, when produced
};

bool is_admin();

Result sfc();    // ~5-20 minutes
Result dism();   // ~10-30 minutes, needs internet for some fixes

// Convenience for the UI: both tools in order, logging each step.
struct FullResult {
    Result sfc;
    Result dism;
    std::wstring summary;
};
FullResult run_all();

}  // namespace ro::win_repair
