#pragma once
#include <filesystem>
#include <string>
#include <vector>

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

namespace ro::icon {

// GDI+ must be up before any drawing happens.
bool init();
void shutdown();

// Draws the "Rust Optimizer" mark (hex plate, gear ring, bolt) at the requested
// size. The returned icon is owned by the caller (DestroyIcon).
HICON create(int size);

// Writes a multi-resolution .ico file. Entries are stored as PNG frames
// (supported by Windows Vista and newer).
bool write_ico_file(const std::filesystem::path& file, const std::vector<int>& sizes,
                    std::string& error);

}  // namespace ro::icon
