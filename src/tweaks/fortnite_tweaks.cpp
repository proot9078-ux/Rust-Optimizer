#include "ro/fortnite_tweaks.hpp"

#include <algorithm>
#include <map>

#include "ro/backup.hpp"
#include "ro/epic.hpp"
#include "ro/fs.hpp"
#include "ro/ini.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"

namespace ro::fortnite {

namespace {
constexpr const char* kEngineBlock = "fortnite-engine";
constexpr const char* kGameBlock = "fortnite-game";
}  // namespace

Paths resolve_user_paths() {
    Paths p;
    p.config_dir = epic::user_config_dir();
    p.game_user_settings = p.config_dir / L"GameUserSettings.ini";
    p.engine_ini = p.config_dir / L"Engine.ini";
    p.game_ini = p.config_dir / L"Game.ini";
    return p;
}

Paths resolve_paths(const std::filesystem::path& fortnite_exe) {
    Paths p = resolve_user_paths();
    if (!fortnite_exe.empty()) p.install_dir = fortnite_exe.parent_path();
    return p;
}

json::Value to_json(const Options& o) {
    json::Value j = json::Value::object();
    j["vsync_off"] = o.vsync_off;
    j["unlimited_fps"] = o.unlimited_fps;
    j["frame_rate_limit"] = o.frame_rate_limit;
    j["fullscreen"] = o.fullscreen;
    j["motion_blur_off"] = o.motion_blur_off;
    j["bloom_off"] = o.bloom_off;
    j["lens_flare_off"] = o.lens_flare_off;
    j["depth_of_field_off"] = o.depth_of_field_off;
    j["shadow_tweak"] = o.shadow_tweak;
    j["shadow_resolution"] = o.shadow_resolution;
    j["streaming_pool"] = o.streaming_pool;
    j["pool_size_mb"] = o.pool_size_mb;
    j["dynamic_res_off"] = o.dynamic_res_off;
    j["nanite_off"] = o.nanite_off;
    return j;
}

Options from_json(const json::Value& v) {
    Options o;
    if (!v.is_object()) return o;
    o.vsync_off = json::get_bool(v, "vsync_off", o.vsync_off);
    o.unlimited_fps = json::get_bool(v, "unlimited_fps", o.unlimited_fps);
    o.frame_rate_limit = static_cast<int>(json::get_int(v, "frame_rate_limit", o.frame_rate_limit));
    o.fullscreen = json::get_bool(v, "fullscreen", o.fullscreen);
    o.motion_blur_off = json::get_bool(v, "motion_blur_off", o.motion_blur_off);
    o.bloom_off = json::get_bool(v, "bloom_off", o.bloom_off);
    o.lens_flare_off = json::get_bool(v, "lens_flare_off", o.lens_flare_off);
    o.depth_of_field_off = json::get_bool(v, "depth_of_field_off", o.depth_of_field_off);
    o.shadow_tweak = json::get_bool(v, "shadow_tweak", o.shadow_tweak);
    o.shadow_resolution = static_cast<int>(json::get_int(v, "shadow_resolution", o.shadow_resolution));
    o.streaming_pool = json::get_bool(v, "streaming_pool", o.streaming_pool);
    o.pool_size_mb = static_cast<int>(json::get_int(v, "pool_size_mb", o.pool_size_mb));
    o.dynamic_res_off = json::get_bool(v, "dynamic_res_off", o.dynamic_res_off);
    o.nanite_off = json::get_bool(v, "nanite_off", o.nanite_off);
    return o;
}

ApplyReport apply(const Paths& p, const Options& opt) {
    ApplyReport report;
    if (!fsx::is_directory(p.config_dir)) {
        report.notes.push_back("Конфигурация Fortnite не найдена: " + str::narrow(p.config_dir.wstring()));
        report.notes.push_back("Запустите Fortnite один раз, чтобы игра создала файлы настроек");
        return report;
    }

    const std::filesystem::path files[] = {p.game_user_settings, p.engine_ini, p.game_ini};
    for (const auto& f : files) {
        if (!fsx::is_regular_file(f)) {
            // Create empty files only for the ones we intend to write.
            if (f == p.game_user_settings || f == p.engine_ini) {
                fsx::write_text(f, "");
            }
        }
    }

    const auto backup_dir = backup::create("fortnite-cfg");
    std::string error;
    bool backup_ok = false;
    for (const auto& f : files) {
        if (!fsx::is_regular_file(f)) continue;
        std::string e;
        if (backup::add_file(backup_dir, f, "fortnite " + str::narrow(f.filename().wstring()), e)) backup_ok = true;
        else error = e;
    }
    if (!backup_ok) {
        report.notes.push_back("Бэкап не создан: " + (error.empty() ? "нет файлов настроек" : error));
        return report;
    }
    report.backup_dir = str::narrow(backup_dir.wstring());

    // ---- GameUserSettings.ini -------------------------------------------------
    {
        IniFile ini = IniFile::parse(fsx::read_text(p.game_user_settings).value_or(""));
        if (!ini.has("ScalabilityGroups", "sg.ViewDistanceQuality") &&
            !ini.has("/Script/FortniteGame.FortniteGameUserSettings", "FrameRateLimit")) {
            // Nothing we recognise: still safe to add the well-known section.
        }
        int changed = 0;
        const auto set = [&](const char* section, const char* key, const std::string& value) {
            ++report.total;
            if (ini.set(section, key, value)) ++changed;
            ++report.applied;
        };

        set("/Script/FortniteGame.FortniteGameUserSettings", "bUseVSync", opt.vsync_off ? "False" : "True");
        if (opt.unlimited_fps) {
            set("/Script/FortniteGame.FortniteGameUserSettings", "FrameRateLimit", "0.000000");
        } else {
            set("/Script/FortniteGame.FortniteGameUserSettings", "FrameRateLimit",
                str::fmt("%d.000000", opt.frame_rate_limit));
        }
        if (opt.fullscreen) {
            set("/Script/FortniteGame.FortniteGameUserSettings", "FullscreenMode", "0");
            set("/Script/FortniteGame.FortniteGameUserSettings", "LastConfirmedFullscreenMode", "0");
            set("/Script/FortniteGame.FortniteGameUserSettings", "PreferredFullscreenMode", "0");
        }
        if (opt.dynamic_res_off) {
            set("/Script/FortniteGame.FortniteGameUserSettings", "bUseDynamicResolution", "False");
        }
        if (changed > 0) {
            if (!fsx::write_text_atomic(p.game_user_settings, ini.serialize())) {
                report.notes.push_back("Не удалось записать GameUserSettings.ini");
                return report;
            }
            report.notes.push_back(str::fmt("GameUserSettings.ini: обновлено %d значений", changed));
        } else {
            report.notes.push_back("GameUserSettings.ini: изменений не требуется");
        }
    }

    // ---- Engine.ini [SystemSettings] -----------------------------------------
    {
        IniFile ini = IniFile::parse(fsx::read_text(p.engine_ini).value_or(""));
        std::vector<std::string> lines;
        if (opt.motion_blur_off) lines.push_back("r.DefaultFeature.MotionBlur=0");
        if (opt.bloom_off) lines.push_back("r.BloomQuality=0");
        if (opt.lens_flare_off) lines.push_back("r.LensFlareQuality=0");
        if (opt.depth_of_field_off) lines.push_back("r.DepthOfFieldQuality=0");
        if (opt.shadow_tweak) {
            lines.push_back("r.Shadow.MaxResolution=" + std::to_string(opt.shadow_resolution));
            lines.push_back("r.Shadow.CSM.MaxCascades=1");
        }
        if (opt.streaming_pool) lines.push_back("r.Streaming.PoolSize=" + std::to_string(opt.pool_size_mb));
        if (opt.nanite_off) lines.push_back("r.Nanite=0");

        if (lines.empty()) {
            ini.remove_marked_block(kEngineBlock);
        } else {
            ini.set_marked_block("SystemSettings", kEngineBlock, lines);
        }
        if (!fsx::write_text_atomic(p.engine_ini, ini.serialize())) {
            report.notes.push_back("Не удалось записать Engine.ini");
            return report;
        }
        report.notes.push_back(str::fmt("Engine.ini: %zu параметров в блоке RO", lines.size()));
        report.applied += static_cast<int>(lines.size());
        report.total += static_cast<int>(lines.size());
    }

    // ---- Game.ini [PatchNotes] -----------------------------------------------
    // Frame-rate smoothing is handled by the engine automatically; we only add
    // the low-latency switch when the user asked for it.
    if (opt.unlimited_fps) {
        IniFile ini = IniFile::parse(fsx::read_text(p.game_ini).value_or(""));
        ini.set_marked_block("PatchNotes", kGameBlock, {"UseVSync=False"});
        fsx::write_text_atomic(p.game_ini, ini.serialize());
    }

    report.ok = true;
    log::success("fortnite: configuration applied");
    return report;
}

ApplyReport revert(const Paths& p, const std::filesystem::path& backup_dir) {
    ApplyReport report;
    const std::filesystem::path dir = backup_dir.empty() ? backup::latest_for("fortnite GameUserSettings.ini") : backup_dir;
    if (!dir.empty()) {
        std::string error;
        if (backup::restore(dir, error)) {
            report.ok = true;
            report.notes.push_back("Конфиги Fortnite восстановлены из " + str::narrow(dir.filename().wstring()));
            return report;
        }
        report.notes.push_back("Откат из бэкапа не удался: " + error);
    }
    // Without a backup, at least strip our generated blocks.
    int removed = 0;
    for (const auto& [path, id] : {std::pair{p.engine_ini, kEngineBlock}, std::pair{p.game_ini, kGameBlock}}) {
        const auto text = fsx::read_text(path);
        if (!text) continue;
        IniFile ini = IniFile::parse(*text);
        if (ini.remove_marked_block(id)) {
            if (fsx::write_text_atomic(path, ini.serialize())) ++removed;
        }
    }
    report.ok = removed > 0;
    report.notes.push_back(removed > 0 ? "Удалены блоки RO из ini-файлов"
                                       : "Нечего откатывать: бэкап и блоки RO не найдены");
    return report;
}

}  // namespace ro::fortnite
