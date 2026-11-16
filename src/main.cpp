#include <windows.h>
#include <shellapi.h>

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/ui/app_window.hpp"
#include "ro/updater.hpp"
#include "ro/version.hpp"

namespace {

// A GUI-subsystem binary has no std handles even when started from a console,
// so attach to the parent console (or create one) before printing.
void attach_console() {
    // Inherited stdout/stderr (pipe or file) is kept intact: it is what CI reads.
    // Only attach to the parent console so interactive users see the output.
    ::AttachConsole(ATTACH_PARENT_PROCESS);
}

std::vector<std::wstring> command_line_args() {
    std::vector<std::wstring> args;
    int argc = 0;
    LPWSTR* argv = ::CommandLineToArgvW(::GetCommandLineW(), &argc);
    if (!argv) return args;
    for (int i = 0; i < argc; ++i) args.emplace_back(argv[i]);
    ::LocalFree(argv);
    return args;
}

void usage() {
    std::printf("%s %s\n", ro::kAppName, ro::kVersion);
    std::printf("Usage: RustOptimizer [--version] [--selftest] [--help]\n");
    std::printf("  --version   print the version and exit\n");
    std::printf("  --selftest  print a diagnostics report (hardware, games, paths)\n");
    std::printf("  --help      show this text\n");
    std::printf("\nWithout arguments the graphical interface starts.\n");
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int) {
    const auto args = command_line_args();
    const auto has = [&](const wchar_t* flag) {
        for (const auto& a : args) {
            if (_wcsicmp(a.c_str(), flag) == 0) return true;
        }
        return false;
    };

    // Internal helper mode used by the updater: the newly downloaded build waits
    // for this process to exit, replaces the binary and relaunches it.
    if (has(L"--apply-update")) {
        for (std::size_t i = 1; i + 3 < args.size(); ++i) {
            if (_wcsicmp(args[i].c_str(), L"--apply-update") != 0) continue;
            const std::filesystem::path staged = args[i + 1];
            const std::filesystem::path target = args[i + 2];
            const auto parent = static_cast<std::uint32_t>(std::wcstoul(args[i + 3].c_str(), nullptr, 10));
            return ro::update::run_applier(staged, target, parent);
        }
        return 2;
    }

    if (has(L"--version") || has(L"-v")) {
        attach_console();
        return ro::ui::print_version();
    }
    if (has(L"--selftest")) {
        attach_console();
        return ro::ui::selftest();
    }
    if (has(L"--help") || has(L"-h") || has(L"/?")) {
        attach_console();
        usage();
        return 0;
    }

    ro::ui::StartOptions options;
    options.instance = instance;
    options.command_line = ::GetCommandLineW();
    return ro::ui::run(options);
}
