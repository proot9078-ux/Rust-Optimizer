#pragma once
#include <string>
#include <vector>

namespace ro {

// Outcome of applying a group of tweaks. `notes` is human readable and is
// mirrored into the UI log.
struct ApplyReport {
    bool ok = false;
    int applied = 0;
    int skipped = 0;
    int total = 0;
    std::string backup_dir;
    std::vector<std::string> notes;
};

}  // namespace ro
