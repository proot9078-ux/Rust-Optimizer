#pragma once
#include <string>

#include "ro/hardware.hpp"

// Derives a concrete, explainable tuning profile from the detected hardware.
//
// Everything here is advisory: the values feed client.cfg, the Fortnite
// texture pool and the Steam launch options, and every write is backed up and
// revertible. No game process is touched, so Easy Anti-Cheat has nothing to
// see — the Zero-Ban policy holds.
namespace ro::tuning {

struct Profile {
    unsigned ram_mb = 0;
    int gc_buffer_mb = 2048;  // RUST gc.buffer: 1024 / 2048 / 4096
    int max_mem_mb = 0;       // -maxMem: 75% of RAM, clamped to [4096, 24576]
    int pool_size_mb = 2048;  // Fortnite texture streaming pool
    bool lowres = false;      // 85% render scale is worth the softness
    bool low_preset = false;  // weak GPU: shadows off + minimum quality
    std::string launch_options;
    std::wstring summary;     // one human-readable line for the UI
};

Profile tune(const HardwareInfo& hw);

}  // namespace ro::tuning
