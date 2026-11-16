#pragma once
#include <filesystem>
#include <string>

namespace ro::shortcut {

// Creates (or refreshes) "Rust Optimizer.lnk" on the current user's desktop
// pointing at `exe`. The icon is taken from the executable itself.
bool create_desktop(const std::filesystem::path& exe, std::string* error = nullptr);

// Same shortcut in the Start menu (Programs folder), so the app can be found
// after the installer-free update replaced the binary.
bool create_start_menu(const std::filesystem::path& exe, std::string* error = nullptr);

// Both of the above; returns true when at least the desktop link exists.
bool ensure(const std::filesystem::path& exe);

}  // namespace ro::shortcut
