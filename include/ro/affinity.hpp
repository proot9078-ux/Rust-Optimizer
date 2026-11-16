#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace ro::cpu {

struct Topology {
    unsigned logical = 0;
    unsigned physical = 0;
    unsigned performance_cores = 0;
    unsigned efficiency_cores = 0;
    bool hybrid = false;          // Intel P/E-core or any non-uniform efficiency
    bool has_3d_vcache = false;   // AMD X3D: asymmetric L3 per CCD
    std::uint64_t l3_total_bytes = 0;
    std::uint64_t l3_max_bytes = 0;
    std::uint64_t l3_min_bytes = 0;
    std::wstring cpu_name;
    // Affinity masks. valid_* is false when the feature does not apply.
    bool pcore_mask_valid = false;
    std::uint64_t pcore_mask = 0;
    bool x3d_mask_valid = false;
    std::uint64_t x3d_mask = 0;
    std::wstring summary;   // one-line human readable description
    std::wstring note;      // caveat shown in the UI
};

Topology detect();
// Mask that keeps the game on the fastest cores (P-cores / 3D V-Cache CCD).
std::uint64_t recommended_mask(const Topology& t);
// All logical processors in group 0 (affinity is group-bound on >64 CPU hosts).
std::uint64_t all_cores_mask(const Topology& t);

}  // namespace ro::cpu
