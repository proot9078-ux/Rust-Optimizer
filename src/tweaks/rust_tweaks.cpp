#include "ro/rust_tweaks.hpp"

#include <algorithm>
#include <cctype>
#include <map>

#include "ro/backup.hpp"
#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro::rust {

namespace {

constexpr const char* kBlockId = "rust-tweaks";

// client.cfg is a plain "convar value" file. Both "key value" and "key=value"
// spellings are accepted so a hand-edited file keeps working.
class CfgFile {
public:
    static CfgFile parse(std::string_view text) {
        CfgFile f;
        f.crlf_ = text.find("\r\n") != std::string_view::npos;
        for (const auto& raw : str::split_lines(str::normalise_newlines(text))) {
            Line l;
            l.raw = raw;
            const std::string t = str::trim(raw);
            if (!t.empty() && t[0] != ';' && t[0] != '#' && t[0] != '[') {
                std::size_t split = t.find_first_of(" \t=");
                if (split == std::string::npos) {
                    l.key = t;
                    l.value.clear();
                } else {
                    l.key = str::trim(t.substr(0, split));
                    l.value = str::trim(t.substr(split + 1));
                }
                l.has_key = !l.key.empty();
            }
            f.lines_.push_back(std::move(l));
        }
        return f;
    }

    bool has(std::string_view key) const {
        return std::any_of(lines_.begin(), lines_.end(),
                           [&](const Line& l) { return l.has_key && str::iequals(l.key, key); });
    }

    std::string get(std::string_view key) const {
        for (const auto& l : lines_) {
            if (l.has_key && str::iequals(l.key, key)) return l.value;
        }
        return {};
    }

    int set(std::string_view key, std::string_view value) {
        for (auto& l : lines_) {
            if (l.has_key && str::iequals(l.key, key)) {
                if (l.value == value) return 0;
                l.value = std::string(value);
                l.raw.clear();
                return 1;
            }
        }
        return 0;
    }

    bool remove_block() {
        const std::string open = std::string("; >>> RO:") + kBlockId + " >>>";
        const std::string close = std::string("; <<< RO:") + kBlockId + " <<<";
        bool inside = false;
        bool removed = false;
        std::vector<Line> keep;
        keep.reserve(lines_.size());
        for (auto& l : lines_) {
            if (!inside && str::contains(l.raw, open)) {
                inside = true;
                removed = true;
                continue;
            }
            if (inside) {
                if (str::contains(l.raw, close)) inside = false;
                continue;
            }
            keep.push_back(std::move(l));
        }
        lines_ = std::move(keep);
        return removed;
    }

    void append_block(const std::vector<std::pair<std::string, std::string>>& kv) {
        if (kv.empty()) return;
        // Trim trailing blank lines so the block sits at the end of the file.
        while (!lines_.empty() && str::trim(lines_.back().raw).empty() && !lines_.back().has_key) {
            lines_.pop_back();
        }
        Line open;
        open.raw = std::string("; >>> RO:") + kBlockId + " >>>";
        lines_.push_back(open);
        for (const auto& [k, v] : kv) {
            Line l;
            l.has_key = true;
            l.key = k;
            l.value = v;
            lines_.push_back(std::move(l));
        }
        Line close;
        close.raw = std::string("; <<< RO:") + kBlockId + " <<<";
        lines_.push_back(close);
    }

    bool has_block() const {
        const std::string open = std::string("; >>> RO:") + kBlockId + " >>>";
        return std::any_of(lines_.begin(), lines_.end(), [&](const Line& l) { return str::contains(l.raw, open); });
    }

    std::string serialize() const {
        const std::string nl = crlf_ ? "\r\n" : "\n";
        std::string out;
        out.reserve(lines_.size() * 32);
        for (const auto& l : lines_) {
            if (l.has_key) {
                if (!l.raw.empty()) {
                    out += l.raw;  // untouched line, keep the original spelling
                } else {
                    out += l.key;
                    out += ' ';
                    out += l.value;
                }
            } else {
                out += l.raw;
            }
            out += nl;
        }
        return out;
    }

private:
    struct Line {
        std::string raw;
        std::string key;
        std::string value;
        bool has_key = false;
    };
    std::vector<Line> lines_;
    bool crlf_ = false;
};

}  // namespace

Paths resolve_paths(const std::filesystem::path& rust_exe) {
    Paths p;
    if (rust_exe.empty()) return p;
    p.install_dir = rust_exe.parent_path();
    p.cfg_dir = p.install_dir / L"cfg";
    p.client_cfg = p.cfg_dir / L"client.cfg";
    p.keys_cfg = p.cfg_dir / L"keys.cfg";
    return p;
}

json::Value to_json(const Options& o) {
    json::Value j = json::Value::object();
    j["grass_off"] = o.grass_off;
    j["grass_displacement"] = o.grass_displacement;
    j["grass_shadowcast"] = o.grass_shadowcast;
    j["grass_shadowreceive"] = o.grass_shadowreceive;
    j["ssaa_off"] = o.ssaa_off;
    j["vsync_off"] = o.vsync_off;
    j["shadows_off"] = o.shadows_off;
    j["half_res_sss"] = o.half_res_sss;
    j["pixellight_off"] = o.pixellight_off;
    j["depth_of_field_off"] = o.depth_of_field_off;
    j["motion_blur_off"] = o.motion_blur_off;
    j["parallax_off"] = o.parallax_off;
    j["shafts_off"] = o.shafts_off;
    j["chromatic_off"] = o.chromatic_off;
    j["quality_low"] = o.quality_low;
    j["maxdecals_off"] = o.maxdecals_off;
    j["occlusion_on"] = o.occlusion_on;
    j["lowres"] = o.lowres;
    j["clouds_off"] = o.clouds_off;
    j["fog_off"] = o.fog_off;
    j["gc_buffer"] = o.gc_buffer;
    j["gc_buffer_mb"] = o.gc_buffer_mb;
    j["net_backup"] = o.net_backup;
    j["launcher_gpu_high"] = o.launcher_gpu_high;
    j["launch_options"] = o.launch_options;
    return j;
}

Options from_json(const json::Value& v) {
    Options o;
    if (!v.is_object()) return o;
    o.grass_off = json::get_bool(v, "grass_off", o.grass_off);
    o.grass_displacement = json::get_bool(v, "grass_displacement", o.grass_displacement);
    o.grass_shadowcast = json::get_bool(v, "grass_shadowcast", o.grass_shadowcast);
    o.grass_shadowreceive = json::get_bool(v, "grass_shadowreceive", o.grass_shadowreceive);
    o.ssaa_off = json::get_bool(v, "ssaa_off", o.ssaa_off);
    o.vsync_off = json::get_bool(v, "vsync_off", o.vsync_off);
    o.shadows_off = json::get_bool(v, "shadows_off", o.shadows_off);
    o.half_res_sss = json::get_bool(v, "half_res_sss", o.half_res_sss);
    o.pixellight_off = json::get_bool(v, "pixellight_off", o.pixellight_off);
    o.depth_of_field_off = json::get_bool(v, "depth_of_field_off", o.depth_of_field_off);
    o.motion_blur_off = json::get_bool(v, "motion_blur_off", o.motion_blur_off);
    o.parallax_off = json::get_bool(v, "parallax_off", o.parallax_off);
    o.shafts_off = json::get_bool(v, "shafts_off", o.shafts_off);
    o.chromatic_off = json::get_bool(v, "chromatic_off", o.chromatic_off);
    o.quality_low = json::get_bool(v, "quality_low", o.quality_low);
    o.maxdecals_off = json::get_bool(v, "maxdecals_off", o.maxdecals_off);
    o.occlusion_on = json::get_bool(v, "occlusion_on", o.occlusion_on);
    o.lowres = json::get_bool(v, "lowres", o.lowres);
    o.clouds_off = json::get_bool(v, "clouds_off", o.clouds_off);
    o.fog_off = json::get_bool(v, "fog_off", o.fog_off);
    o.gc_buffer = json::get_bool(v, "gc_buffer", o.gc_buffer);
    o.gc_buffer_mb = static_cast<int>(json::get_int(v, "gc_buffer_mb", o.gc_buffer_mb));
    o.net_backup = json::get_bool(v, "net_backup", o.net_backup);
    o.launcher_gpu_high = json::get_bool(v, "launcher_gpu_high", o.launcher_gpu_high);
    o.launch_options = json::get_string(v, "launch_options", o.launch_options);
    return o;
}

ApplyReport apply(const Paths& p, const Options& opt) {
    ApplyReport report;
    if (p.client_cfg.empty()) {
        report.notes.push_back("RUST не найден: client.cfg недоступен");
        return report;
    }
    if (!fsx::is_directory(p.cfg_dir)) {
        report.notes.push_back("Папка cfg отсутствует: " + str::narrow(p.cfg_dir.wstring()));
        return report;
    }

    const auto existing = fsx::read_text(p.client_cfg);
    if (!existing) {
        report.notes.push_back("client.cfg не читается (нет прав?)");
        return report;
    }

    // 1. Backup first, always.
    std::string backup_error;
    const auto backup_dir = backup::create("rust-cfg");
    if (!backup::add_file(backup_dir, p.client_cfg, "rust client.cfg", backup_error)) {
        report.notes.push_back("Бэкап не создан: " + backup_error);
        return report;
    }
    report.backup_dir = str::narrow(backup_dir.wstring());

    CfgFile cfg = CfgFile::parse(*existing);
    std::vector<std::pair<std::string, std::string>> desired = {
        {"grass.on", "false"},
        {"grass.displacement", "false"},
        {"grass.shadowcast", "false"},
        {"grass.shadowreceive", "false"},
        {"graphics.ssaa", "false"},
        {"graphics.vsync", "0"},
        {"shadow.on", "false"},
        {"sss.halfres", "True"},
        {"graphicssettings.pixellightcount", "0"},
        {"graphics.depthoffield", "false"},
        {"graphics.motionblur", "false"},
        {"graphics.parallax", "false"},
        {"graphics.shafts", "false"},
        {"graphics.chromaticaberration", "false"},
        {"graphics.volumetricclouds", "false"},
        {"graphics.volumetricfog", "false"},
    };
    // Quality sliders are numeric: writing "true" there would be ignored by the
    // game, so they are appended only when the user asked for the minimum.
    if (opt.quality_low) {
        desired.emplace_back("graphics.grassquality", "0");
        desired.emplace_back("graphics.globalreflectionquality", "0");
        desired.emplace_back("graphics.waterquality", "0");
        desired.emplace_back("graphics.effectquality", "0");
        desired.emplace_back("graphics.skinquality", "0");
        desired.emplace_back("graphics.objectquality", "0");
        desired.emplace_back("graphics.shadowquality", "1");
    }
    if (opt.maxdecals_off) desired.emplace_back("graphics.maxdecals", "0");
    if (opt.occlusion_on) desired.emplace_back("graphics.occlusionculling", "true");
    if (opt.lowres) desired.emplace_back("graphics.renderscale", "0.85");
    if (opt.gc_buffer) desired.emplace_back("gc.buffer", std::to_string(opt.gc_buffer_mb));

    const std::map<std::string, bool> enabled = {
        {"grass.on", opt.grass_off},
        {"grass.displacement", opt.grass_displacement},
        {"grass.shadowcast", opt.grass_shadowcast},
        {"grass.shadowreceive", opt.grass_shadowreceive},
        {"graphics.ssaa", opt.ssaa_off},
        {"graphics.vsync", opt.vsync_off},
        {"shadow.on", opt.shadows_off},
        {"sss.halfres", opt.half_res_sss},
        {"graphicssettings.pixellightcount", opt.pixellight_off},
        {"graphics.depthoffield", opt.depth_of_field_off},
        {"graphics.motionblur", opt.motion_blur_off},
        {"graphics.parallax", opt.parallax_off},
        {"graphics.shafts", opt.shafts_off},
        {"graphics.chromaticaberration", opt.chromatic_off},
        {"graphics.volumetricclouds", opt.clouds_off},
        {"graphics.volumetricfog", opt.fog_off},
    };

    int changed = 0;
    std::vector<std::pair<std::string, std::string>> append;
    for (const auto& [key, value] : desired) {
        const auto it = enabled.find(key);
        if (it != enabled.end() && !it->second) continue;
        ++report.total;
        if (cfg.has(key)) {
            changed += cfg.set(key, value);
            ++report.applied;
        } else {
            append.emplace_back(key, value);
            ++report.applied;
        }
    }

    cfg.remove_block();
    cfg.append_block(append);

    if (changed == 0 && append.empty() && !cfg.has_block()) {
        report.notes.push_back("client.cfg уже содержит все выбранные параметры");
        report.ok = true;
        return report;
    }

    const std::string text = cfg.serialize();
    if (!fsx::write_text_atomic(p.client_cfg, text)) {
        report.notes.push_back("Не удалось записать client.cfg");
        return report;
    }

    // 2. Verify by re-reading: a truncated write would be a silent data loss.
    const auto verify = fsx::read_text(p.client_cfg);
    if (!verify || verify->size() != text.size()) {
        report.notes.push_back("Проверка записи не удалась, восстанавливаю из бэкапа");
        std::string restore_error;
        const auto backup_file = backup_dir / p.client_cfg.filename();
        if (fsx::copy_file(backup_file, p.client_cfg, true)) {
            report.notes.push_back("Исходный файл восстановлен");
        } else {
            report.notes.push_back("Восстановление из бэкапа не удалось: " + restore_error);
        }
        return report;
    }

    report.ok = true;
    report.notes.push_back(str::fmt("client.cfg обновлён: %d параметров (изменено %d, добавлено %zu)", report.applied,
                                    changed, append.size()));
    log::success("rust: client.cfg updated");
    return report;
}

ApplyReport revert(const Paths& p, const std::filesystem::path& backup_dir) {
    ApplyReport report;
    if (p.client_cfg.empty()) {
        report.notes.push_back("RUST не найден");
        return report;
    }
    std::filesystem::path dir = backup_dir;
    if (dir.empty()) dir = backup::latest_for("rust client.cfg");
    if (dir.empty()) {
        // No backup at all: at least remove our generated block.
        const auto text = fsx::read_text(p.client_cfg);
        if (!text) {
            report.notes.push_back("client.cfg не читается");
            return report;
        }
        CfgFile cfg = CfgFile::parse(*text);
        if (!cfg.remove_block()) {
            report.notes.push_back("Бэкап не найден, удалять нечего");
            return report;
        }
        if (!fsx::write_text_atomic(p.client_cfg, cfg.serialize())) {
            report.notes.push_back("Не удалось записать client.cfg");
            return report;
        }
        report.ok = true;
        report.notes.push_back("Удалён блок твиков; изменения существующих строк не откатывались");
        return report;
    }

    std::string error;
    if (!backup::restore(dir, error)) {
        report.notes.push_back("Откат не удался: " + error);
        return report;
    }
    report.ok = true;
    report.notes.push_back("client.cfg восстановлен из " + str::narrow(dir.filename().wstring()));
    return report;
}

std::string recommended_launch_options(unsigned ram_mb, const std::string& gpu_vendor) {
    std::string out = "-high";
    if (ram_mb > 0) out += " -maxMem=" + std::to_string(ram_mb);
    out += " -malloc=system";
    if (gpu_vendor == "intel") out += " -force-d3d11";
    if (ram_mb >= 32000) {
        out += " -gc.buffer 4096";
    } else if (ram_mb >= 15000) {
        out += " -gc.buffer 2048";
    }
    return out;
}

}  // namespace ro::rust
