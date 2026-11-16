#pragma once
#include <windows.h>

#include <string>

namespace ro::ui {

struct StartOptions {
    HINSTANCE instance = nullptr;
    std::wstring command_line;
};

// Creates the main window and runs the message loop. Returns the exit code.
int run(const StartOptions& options);

// Console mode entry points (CI / troubleshooting).
int selftest();                        // detects games, prints a diagnostics report
int print_version();

}  // namespace ro::ui
