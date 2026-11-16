#include "ro/affinity.hpp"

#include <windows.h>

#include <algorithm>
#include <map>
#include <vector>

#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::cpu {

namespace {

std::wstring read_cpu_name() {
    auto name = win::reg_read_string(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                                     L"ProcessorNameString");
    if (!name) return L"Unknown CPU";
    return str::trim(*name);
}

struct CacheInfo {
    int level = 0;
    std::uint64_t size = 0;
    std::uint64_t mask = 0;
    int type = 0;  // CACHE_UNIFIED == 2
};

std::vector<std::uint64_t> core_masks(std::vector<int>* efficiency_classes) {
    std::vector<std::uint64_t> masks;
    if (efficiency_classes) efficiency_classes->clear();
    DWORD len = 0;
    ::GetLogicalProcessorInformationEx(RelationProcessorCore, nullptr, &len);
    if (len == 0) return masks;
    std::vector<unsigned char> buffer(len);
    if (!::GetLogicalProcessorInformationEx(RelationProcessorCore,
                                            reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buffer.data()),
                                            &len)) {
        return masks;
    }
    std::size_t offset = 0;
    while (offset < len) {
        const auto* info = reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(buffer.data() + offset);
        if (info->Relationship == RelationProcessorCore) {
            std::uint64_t mask = 0;
            for (WORD g = 0; g < info->Processor.GroupCount; ++g) {
                mask |= static_cast<std::uint64_t>(info->Processor.GroupMask[g].Mask);
            }
            masks.push_back(mask);
            if (efficiency_classes) efficiency_classes->push_back(info->Processor.EfficiencyClass);
        }
        if (info->Size == 0) break;
        offset += info->Size;
    }
    return masks;
}

std::vector<CacheInfo> l3_caches() {
    std::vector<CacheInfo> out;
    DWORD len = 0;
    ::GetLogicalProcessorInformationEx(RelationCache, nullptr, &len);
    if (len == 0) return out;
    std::vector<unsigned char> buffer(len);
    if (!::GetLogicalProcessorInformationEx(RelationCache,
                                            reinterpret_cast<PSYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX>(buffer.data()),
                                            &len)) {
        return out;
    }
    std::size_t offset = 0;
    while (offset < len) {
        const auto* info = reinterpret_cast<const SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX*>(buffer.data() + offset);
        if (info->Relationship == RelationCache && info->Cache.Level == 3) {
            CacheInfo c;
            c.level = info->Cache.Level;
            c.size = info->Cache.CacheSize;
            c.type = info->Cache.Type;
            // CACHE_RELATIONSHIP carries one GROUP_AFFINITY (group 0 on all
            // consumer hosts); multi-group caches are rare and out of scope.
            c.mask |= static_cast<std::uint64_t>(info->Cache.GroupMask.Mask);
            out.push_back(c);
        }
        if (info->Size == 0) break;
        offset += info->Size;
    }
    return out;
}

std::uint64_t sum_masks(const std::vector<std::uint64_t>& masks, const std::vector<std::size_t>& idx) {
    std::uint64_t m = 0;
    for (std::size_t i : idx) m |= masks[i];
    return m;
}

}  // namespace

Topology detect() {
    Topology t;
    t.cpu_name = read_cpu_name();

    SYSTEM_INFO si{};
    ::GetSystemInfo(&si);
    t.logical = si.dwNumberOfProcessors;

    std::vector<int> efficiency;
    const auto masks = core_masks(&efficiency);
    t.physical = static_cast<unsigned>(masks.size());
    if (t.physical == 0) t.physical = t.logical;

    // Hybrid detection: Windows reports EfficiencyClass > 0 for E-cores.
    bool hybrid = false;
    int max_eff = 0;
    for (int e : efficiency) {
        if (e > max_eff) max_eff = e;
        if (e > 0) hybrid = true;
    }
    if (hybrid && max_eff > 0) {
        t.hybrid = true;
        std::vector<std::size_t> p_idx;
        for (std::size_t i = 0; i < efficiency.size(); ++i) {
            if (efficiency[i] == 0) p_idx.push_back(i);
            else t.efficiency_cores++;
        }
        t.performance_cores = static_cast<unsigned>(p_idx.size());
        if (!p_idx.empty() && p_idx.size() < masks.size()) {
            t.pcore_mask = sum_masks(masks, p_idx);
            t.pcore_mask_valid = t.pcore_mask != 0;
        }
    } else {
        t.performance_cores = t.physical;
    }

    const auto caches = l3_caches();
    std::uint64_t l3_total = 0;
    std::uint64_t l3_max = 0;
    std::uint64_t l3_min = 0;
    if (!caches.empty()) {
        l3_min = caches.front().size;
        for (const auto& c : caches) {
            l3_total += c.size;
            l3_max = (std::max)(l3_max, c.size);
            l3_min = (std::min)(l3_min, c.size);
        }
    }
    t.l3_total_bytes = l3_total;
    t.l3_max_bytes = l3_max;
    t.l3_min_bytes = l3_min;

    // AMD 3D V-Cache heuristic: two or more L3 caches where one is larger
    // (X3D CCD pairs the big cache with a smaller one on dual-CCD parts).
    if (caches.size() >= 2 && l3_max > l3_min) {
        t.has_3d_vcache = true;
        std::uint64_t mask = 0;
        for (const auto& c : caches) {
            if (c.size == l3_max) mask |= c.mask;
        }
        if (mask != 0) {
            t.x3d_mask = mask;
            t.x3d_mask_valid = true;
        }
    }

    // One-line summary.
    std::wstring summary = t.cpu_name + L"  •  ";
    summary += str::wfmt(L"%u логических / %u физических", t.logical, t.physical);
    if (t.hybrid) {
        summary += str::wfmt(L"  •  P: %u / E: %u", t.performance_cores, t.efficiency_cores);
    }
    if (t.l3_max_bytes) {
        summary += L"  •  L3 " + str::human_bytes_w(t.l3_max_bytes);
    }
    t.summary = summary;

    if (t.hybrid) t.note = L"Обнаружены P/E-ядра: игра будет закреплена за P-ядрами.";
    else if (t.has_3d_vcache) t.note = L"Обнаружен 3D V-Cache: игра будет закреплена за CCD с большим L3.";
    else t.note = L"Неоднородных ядер не обнаружено — закрепление по ядрам не требуется.";
    if (t.logical > 64) {
        t.note += L" Более 64 логических процессоров: маска ограничена группой 0.";
    }
    return t;
}

std::uint64_t recommended_mask(const Topology& t) {
    if (t.x3d_mask_valid && t.x3d_mask != 0) return t.x3d_mask;
    if (t.pcore_mask_valid && t.pcore_mask != 0) return t.pcore_mask;
    return all_cores_mask(t);
}

std::uint64_t all_cores_mask(const Topology& t) {
    if (t.logical >= 64) return ~0ull;
    return (1ull << t.logical) - 1ull;
}

}  // namespace ro::cpu
