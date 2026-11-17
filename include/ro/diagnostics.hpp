#pragma once
#include <filesystem>
#include <string>

#include "ro/hardware.hpp"
#include "ro/settings.hpp"

namespace ro::diag {

// Writes a plain-text report (system, hardware, games, settings, log tail)
// into %LOCALAPPDATA%\RustOptimizer\reports and returns its path.
std::filesystem::path write_report(const HardwareInfo& hw, const AppSettings& settings,
                                   const std::wstring& rust_dir, const std::wstring& fortnite_dir,
                                   std::string& error);

std::filesystem::path reports_dir();

}  // namespace ro::diag
