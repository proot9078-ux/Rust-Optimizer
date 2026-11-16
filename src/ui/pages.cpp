#include "ro/ui/pages.hpp"

#include <algorithm>

#include "ro/fs.hpp"
#include "ro/memory.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro::ui {

namespace {

std::string key(const std::string& page, const std::string& row) { return page + "." + row; }

bool on(const std::map<std::string, bool>& toggles, const std::string& page, const std::string& row,
        bool fallback = true) {
    const auto it = toggles.find(key(page, row));
    return it == toggles.end() ? fallback : it->second;
}

Row section(const std::string& id, const std::wstring& title) {
    Row r;
    r.kind = RowKind::Section;
    r.id = id;
    r.title = title;
    return r;
}

Row info(const std::string& id, std::wstring title, std::wstring desc) {
    Row r;
    r.kind = RowKind::Info;
    r.id = id;
    r.title = std::move(title);
    r.desc = std::move(desc);
    return r;
}

Row note(const std::string& id, std::wstring text) {
    Row r;
    r.kind = RowKind::Note;
    r.id = id;
    r.title = std::move(text);
    return r;
}

Row toggle_row(const std::string& id, std::wstring title, std::wstring desc, bool value, bool danger = false) {
    Row r;
    r.kind = RowKind::Toggle;
    r.id = id;
    r.title = std::move(title);
    r.desc = std::move(desc);
    r.on = value;
    r.danger = danger;
    return r;
}

Row button(const std::string& id, std::wstring title, std::string action, bool primary = false,
           bool enabled = true) {
    Row r;
    r.kind = RowKind::Button;
    r.id = id;
    r.title = std::move(title);
    r.action = std::move(action);
    r.primary = primary;
    r.enabled = enabled;
    return r;
}

std::wstring game_status(const GameInstall* g, const wchar_t* label) {
    if (!g || !g->valid) return std::wstring(label) + L" не найден — проверьте установку лаунчера";
    return std::wstring(L"Найден: ") + g->install_dir + L"  (" + g->source + L")";
}

}  // namespace

std::string toggle_key(const std::string& page_id, const std::string& row_id) { return key(page_id, row_id); }

std::map<std::string, bool> default_toggles() {
    return {
        {"overview.auto_priority", true},
        {"overview.auto_purge", false},
        {"rust.grass_off", true},
        {"rust.grass_displacement", false},
        {"rust.grass_shadowcast", false},
        {"rust.grass_shadowreceive", false},
        {"rust.ssaa_off", true},
        {"rust.vsync_off", true},
        {"rust.half_res_sss", true},
        {"rust.pixellight_off", true},
        {"rust.shadows_off", false},
        {"rust.gc_buffer", false},
        {"fortnite.unlimited_fps", true},
        {"fortnite.vsync_off", true},
        {"fortnite.fullscreen", true},
        {"fortnite.motion_blur_off", true},
        {"fortnite.bloom_off", true},
        {"fortnite.lens_flare_off", true},
        {"fortnite.dof_off", true},
        {"fortnite.shadow_tweak", true},
        {"fortnite.streaming_pool", true},
        {"fortnite.dynamic_res_off", false},
        {"system.purge_on_apply", true},
        {"system.dvr_off", false},
        {"system.game_mode_on", true},
        {"system.fse_off", false},
        {"system.hags_on", false},
        {"system.dns_flush", true},
        {"system.tcp_tuning", false},
        {"system.affinity", false},
        {"settings.dark_theme", true},
        {"settings.check_updates", true},
        {"settings.minimize_on_apply", false},
        {"settings.autostart_priority", true},
    };
}

std::vector<Page> build_pages(const PageContext& ctx) {
    std::vector<Page> pages;
    const auto& t = *ctx.toggles;
    const bool admin = ctx.admin;
    const auto snap = mem::snapshot();

    // ---------------------------------------------------------------- overview
    {
        Page p;
        p.id = "overview";
        p.title = L"Обзор";
        p.subtitle = L"Состояние системы, найденные игры и быстрые действия";
        p.apply_label = L"Применить всё";

        p.rows.push_back(info("admin", L"Права",
                              admin ? L"Администратор — доступны standby-список и системные твики"
                                    : L"Обычный пользователь — часть функций потребует перезапуска с правами админа"));
        p.rows.push_back(section("games", L"ИГРЫ"));
        p.rows.push_back(info("rust", L"RUST", game_status(ctx.rust, L"RUST")));
        p.rows.push_back(info("fortnite", L"FORTNITE", game_status(ctx.fortnite, L"FORTNITE")));
        p.rows.push_back(button("detect", L"Переискать игры", "detect", false));

        p.rows.push_back(section("hw", L"ЖЕЛЕЗО"));
        p.rows.push_back(info("cpu", L"Процессор", ctx.cpu ? ctx.cpu->summary : L"—"));
        p.rows.push_back(info("gpu", L"Видеокарта",
                              ctx.hw && ctx.hw->gpu.valid
                                  ? ctx.hw->gpu.name + L"  •  " + str::human_bytes_w(ctx.hw->gpu.vram_bytes) +
                                        L" VRAM"
                                  : L"Не определена"));
        p.rows.push_back(info("ram", L"Память",
                              ctx.hw ? str::human_bytes_w(ctx.hw->ram_bytes) + L"  •  свободно " +
                                           str::human_bytes_w(snap.available_bytes)
                                     : L"—"));
        p.rows.push_back(info("os", L"Система", ctx.hw ? ctx.hw->os_display : L"—"));

        p.rows.push_back(section("quick", L"БЫСТРЫЕ ДЕЙСТВИЯ"));
        p.rows.push_back(toggle_row("auto_priority", L"Держать высокий приоритет игры",
                                    L"Мониторит RustClient.exe и FortniteClient-Win64-Shipping.exe. REALTIME не используется.",
                                    on(t, "overview", "auto_priority")));
        p.rows.push_back(toggle_row("auto_purge", L"Очищать standby-список по таймеру",
                                    L"Каждые 15 минут освобождает кэш страниц. Требуются права администратора.",
                                    on(t, "overview", "auto_purge", false)));
        p.rows.push_back(button("launch_rust", L"Запустить RUST", "launch_rust", true,
                                ctx.rust && ctx.rust->valid));
        p.rows.push_back(button("launch_fortnite", L"Запустить FORTNITE", "launch_fortnite", false,
                                ctx.fortnite && ctx.fortnite->valid));
        pages.push_back(std::move(p));
    }

    // -------------------------------------------------------------------- rust
    {
        Page p;
        p.id = "rust";
        p.title = L"RUST";
        p.subtitle = L"client.cfg, параметры запуска и приоритет процесса";
        p.apply_label = L"Применить к client.cfg";
        p.rows.push_back(section("cfg", L"КОНФИГУРАЦИЯ"));
        p.rows.push_back(info("path", L"client.cfg",
                              ctx.rust && ctx.rust->valid
                                  ? rust::resolve_paths(std::filesystem::path(ctx.rust->exe_path)).client_cfg.wstring()
                                  : L"RUST не найден — файл недоступен"));
        p.rows.push_back(section("visual", L"ГРАФИКА"));
        p.rows.push_back(toggle_row("grass_off", L"Отключить траву  ·  grass.on false",
                                    L"Самый заметный прирост FPS на открытых биомах. Трава не рисуется, дальность видимости сохраняется.",
                                    on(t, "rust", "grass_off")));
        p.rows.push_back(toggle_row("grass_displacement", L"Отключить смещение травы  ·  grass.displacement false",
                                    L"Убирает вершинную анимацию травы — меньше нагрузки на GPU.",
                                    on(t, "rust", "grass_displacement", false)));
        p.rows.push_back(toggle_row("grass_shadowcast", L"Трава не отбрасывает тени  ·  grass.shadowcast false",
                                    L"Снижает число вызовов теневого прохода.", on(t, "rust", "grass_shadowcast", false)));
        p.rows.push_back(toggle_row("grass_shadowreceive", L"Трава не принимает тени",
                                    L"Убирает затенение травы, экономит fill-rate.", on(t, "rust", "grass_shadowreceive", false)));
        p.rows.push_back(toggle_row("ssaa_off", L"Отключить SSAA  ·  graphics.ssaa false",
                                    L"Сглаживание повышенного разрешения — одна из самых дорогих настроек.",
                                    on(t, "rust", "ssaa_off")));
        p.rows.push_back(toggle_row("vsync_off", L"Отключить вертикальную синхронизацию",
                                    L"Ниже задержка ввода, возможен разрыв кадра.", on(t, "rust", "vsync_off")));
        p.rows.push_back(toggle_row("half_res_sss", L"Полуразрешённое подповерхностное рассеивание",
                                    L"sss.halfres True — кожа и листва считаются в половинном разрешении.",
                                    on(t, "rust", "half_res_sss")));
        p.rows.push_back(toggle_row("pixellight_off", L"Отключить точечные источники света",
                                    L"graphicssettings.pixellightcount 0 — меньше динамического освещения.",
                                    on(t, "rust", "pixellight_off")));
        p.rows.push_back(toggle_row("shadows_off", L"Полностью отключить тени  ·  shadow.on false",
                                    L"Максимальный прирост, но противники в тени хуже различимы. Включайте осознанно.",
                                    on(t, "rust", "shadows_off", false), true));
        p.rows.push_back(section("perf", L"ПРОИЗВОДИТЕЛЬНОСТЬ"));
        p.rows.push_back(toggle_row("gc_buffer", L"Увеличить буфер сборщика мусора",
                                    L"gc.buffer 2048 для 16 ГБ RAM, 4096 для 32 ГБ. Реже микрофризы при длинных сессиях.",
                                    on(t, "rust", "gc_buffer", false)));
        p.rows.push_back(note("launch_note",
                              L"Параметры запуска Steam: -high -maxMem=<RAM> -malloc=system -gc.buffer 2048"));
        p.rows.push_back(button("open_cfg", L"Открыть папку cfg", "open_rust_cfg", false,
                                ctx.rust && ctx.rust->valid));
        p.rows.push_back(button("export", L"Экспорт профиля RUST (.rop)", "export_rust", false));
        p.rows.push_back(button("revert", L"Откатить client.cfg из бэкапа", "revert_rust", false,
                                ctx.rust && ctx.rust->valid));
        pages.push_back(std::move(p));
    }

    // ---------------------------------------------------------------- fortnite
    {
        Page p;
        p.id = "fortnite";
        p.title = L"FORTNITE";
        p.subtitle = L"GameUserSettings.ini и Engine.ini — только официальные параметры";
        p.apply_label = L"Применить к конфигам";
        const auto fp = fortnite::resolve_user_paths();
        p.rows.push_back(section("cfg", L"КОНФИГУРАЦИЯ"));
        p.rows.push_back(info("path", L"GameUserSettings.ini", fp.game_user_settings.wstring()));
        p.rows.push_back(info("engine", L"Engine.ini", fp.engine_ini.wstring()));
        p.rows.push_back(section("display", L"ДИСПЛЕЙ"));
        p.rows.push_back(toggle_row("fullscreen", L"Полноэкранный режим",
                                    L"FullscreenMode=0 — нативный эксклюзивный полный экран, минимум задержки.",
                                    on(t, "fortnite", "fullscreen")));
        p.rows.push_back(toggle_row("vsync_off", L"Отключить VSync", L"bUseVSync=False — меньше задержка ввода.",
                                    on(t, "fortnite", "vsync_off")));
        p.rows.push_back(toggle_row("unlimited_fps", L"Снять ограничение FPS",
                                    L"FrameRateLimit=0. Убедитесь, что монитор и GPU справляются.",
                                    on(t, "fortnite", "unlimited_fps")));
        p.rows.push_back(toggle_row("dynamic_res_off", L"Отключить динамическое разрешение",
                                    L"bUseDynamicResolution=False — стабильная картинка без «мыла».",
                                    on(t, "fortnite", "dynamic_res_off", false)));
        p.rows.push_back(section("quality", L"КАЧЕСТВО"));
        p.rows.push_back(toggle_row("motion_blur_off", L"Отключить смазывание движения",
                                    L"r.DefaultFeature.MotionBlur=0.", on(t, "fortnite", "motion_blur_off")));
        p.rows.push_back(toggle_row("bloom_off", L"Отключить bloom", L"r.BloomQuality=0 — меньше постобработки.",
                                    on(t, "fortnite", "bloom_off")));
        p.rows.push_back(toggle_row("lens_flare_off", L"Отключить блики объектива",
                                    L"r.LensFlareQuality=0.", on(t, "fortnite", "lens_flare_off")));
        p.rows.push_back(toggle_row("dof_off", L"Отключить глубину резкости",
                                    L"r.DepthOfFieldQuality=0 — чёткая картинка на дистанции.",
                                    on(t, "fortnite", "dof_off")));
        p.rows.push_back(toggle_row("shadow_tweak", L"Снизить разрешение теней",
                                    L"r.Shadow.MaxResolution=1024 и одна каскадная карта.",
                                    on(t, "fortnite", "shadow_tweak")));
        p.rows.push_back(toggle_row("streaming_pool", L"Настроить пул стриминга текстур",
                                    L"r.Streaming.PoolSize=2048 МБ; для GPU 8+ ГБ VRAM поднимайте до 4096.",
                                    on(t, "fortnite", "streaming_pool")));
        p.rows.push_back(note("launch_note", L"Параметры запуска Epic Games: -high -USEALLAVAILABLECORES"));
        p.rows.push_back(button("open_cfg", L"Открыть папку конфигов", "open_fortnite_cfg", false));
        p.rows.push_back(button("revert", L"Откатить конфиги из бэкапа", "revert_fortnite", false));
        pages.push_back(std::move(p));
    }

    // ------------------------------------------------------------------ system
    {
        Page p;
        p.id = "system";
        p.title = L"Система";
        p.subtitle = L"Память, планировщик, сеть и совместимость с античитами";
        p.apply_label = L"Применить системные твики";
        p.rows.push_back(section("memory", L"ПАМЯТЬ"));
        p.rows.push_back(info("ram", L"Физическая память",
                              str::human_bytes_w(snap.total_bytes) + L"  •  свободно " +
                                  str::human_bytes_w(snap.available_bytes) + L"  •  занято " +
                                  std::to_wstring(snap.load_percent) + L"%"));
        p.rows.push_back(toggle_row("purge_on_apply", L"Очищать standby-список при применении",
                                    L"NtSetSystemInformation + MemoryPurgeStandbyList. Освобождает кэш страниц, снижает статтеры.",
                                    on(t, "system", "purge_on_apply")));
        p.rows.push_back(button("purge", L"Очистить standby-список сейчас", "purge", false, admin));

        p.rows.push_back(section("sched", L"ПЛАНИРОВЩИК И GPU"));
        p.rows.push_back(toggle_row("affinity", L"Закрепить игру за быстрыми ядрами",
                                    ctx.cpu ? ctx.cpu->note : L"Определяется после сканирования железа.",
                                    on(t, "system", "affinity", false), true));
        p.rows.push_back(toggle_row("hags_on", L"Аппаратное планирование GPU (HAGS)",
                                    L"Требует перезагрузки. На части систем снижает задержку, на части — вызывает статтеры.",
                                    on(t, "system", "hags_on", false), true));
        p.rows.push_back(toggle_row("fse_off", L"Отключить оптимизации полного экрана",
                                    L"AppCompatFlags для RustClient.exe и Fortnite — меньше инпут-лага.",
                                    on(t, "system", "fse_off", false)));

        p.rows.push_back(section("gaming", L"ИГРОВЫЕ ФУНКЦИИ WINDOWS"));
        p.rows.push_back(toggle_row("dvr_off", L"Отключить Game DVR",
                                    L"Прекращает фоновую запись — освобождает ресурсы.",
                                    on(t, "system", "dvr_off", false)));
        p.rows.push_back(toggle_row("game_mode_on", L"Включить Game Mode",
                                    L"Приоритет игрового потока при активном окне.",
                                    on(t, "system", "game_mode_on")));
        p.rows.push_back(section("network", L"СЕТЬ"));
        p.rows.push_back(toggle_row("dns_flush", L"Сбросить DNS-кэш",
                                    L"DnsFlushResolverCache. Безопасно, не затрагивает настройки адаптеров.",
                                    on(t, "system", "dns_flush")));
        p.rows.push_back(toggle_row("tcp_tuning", L"Агрессивный TCP-тюнинг",
                                    L"autotuninglevel=restricted. Может ухудшить соединение на нестабильных каналах.",
                                    on(t, "system", "tcp_tuning", false), true));
        p.rows.push_back(button("flush_dns", L"Сбросить DNS-кэш сейчас", "flush_dns", false));
        p.rows.push_back(button("admin", L"Перезапустить от имени администратора", "elevate", false, !admin));
        p.rows.push_back(note("anticheat",
                              L"Приложение не внедряется в процессы и не читает память игры — совместимо с EAC и BattlEye."));
        pages.push_back(std::move(p));
    }

    // ---------------------------------------------------------------- profiles
    {
        Page p;
        p.id = "profiles";
        p.title = L"Профили";
        p.subtitle = L"Переносимые JSON-профили (.rop) — поделиться настройками или вернуться к своим";
        p.has_apply = false;
        p.rows.push_back(section("mine", L"ЛОКАЛЬНЫЕ ПРОФИЛИ"));
        p.rows.push_back(info("dir", L"Папка профилей", fsx::profile_dir().wstring()));
        p.rows.push_back(button("save_rust", L"Сохранить профиль RUST", "profile_save_rust", true));
        p.rows.push_back(button("load_rust", L"Загрузить профиль RUST", "profile_load_rust", false));
        p.rows.push_back(button("save_fortnite", L"Сохранить профиль FORTNITE", "profile_save_fortnite", false));
        p.rows.push_back(button("load_fortnite", L"Загрузить профиль FORTNITE", "profile_load_fortnite", false));
        p.rows.push_back(section("files", L"ФАЙЛЫ"));
        p.rows.push_back(button("export", L"Экспорт профиля RUST в .rop…", "profile_export", false));
        p.rows.push_back(button("import", L"Импорт профиля из .rop…", "profile_import", false));
        p.rows.push_back(button("open", L"Открыть папку профилей", "open_profiles", false));
        p.rows.push_back(note("hint", L"Профиль хранит только настройки твиков, а не файлы игры."));
        pages.push_back(std::move(p));
    }

    // ---------------------------------------------------------------- settings
    {
        Page p;
        p.id = "settings";
        p.title = L"Настройки";
        p.subtitle = L"Внешний вид, обновления и служебные папки";
        p.apply_label = L"Сохранить настройки";
        p.rows.push_back(section("ui", L"ИНТЕРФЕЙС"));
        p.rows.push_back(toggle_row("dark_theme", L"Тёмная тема", L"Светлая тема доступна без перезапуска.",
                                    ctx.settings->dark_theme));
        p.rows.push_back(toggle_row("minimize_on_apply", L"Сворачивать после применения",
                                    L"Удобно, если оптимизатор запускается из лаунчера.", ctx.settings->minimize_on_apply));
        p.rows.push_back(toggle_row("autostart_priority", L"Автоприоритет при старте",
                                    L"Сразу повышает приоритет уже запущенной игры.", ctx.settings->auto_priority));
        p.rows.push_back(section("update", L"ОБНОВЛЕНИЯ"));
        p.rows.push_back(info("auto_update", L"Автообновление",
                              L"Обязательное: новая версия скачивается, распаковывается и "
                              L"запускается автоматически при старте."));
        p.rows.push_back(info("version", L"Версия", str::widen(kVersion)));
        p.rows.push_back(info("latest", L"Последняя версия",
                              ctx.update_available ? str::widen(ctx.latest_version) + L" — доступно обновление"
                                                   : L"Проверка не выполнялась или версия актуальна"));
        p.rows.push_back(button("check", L"Проверить обновления", "update_check", false));
        p.rows.push_back(button("install", L"Установить обновление", "update_install", true, ctx.update_available));
        p.rows.push_back(section("files", L"СЛУЖЕБНЫЕ ПАПКИ"));
        p.rows.push_back(info("data", L"Данные", fsx::data_dir().wstring()));
        p.rows.push_back(info("logs", L"Логи", fsx::log_dir().wstring()));
        p.rows.push_back(button("open_data", L"Открыть папку данных", "open_data", false));
        p.rows.push_back(button("open_logs", L"Открыть логи", "open_logs", false));
        p.rows.push_back(button("reset", L"Сбросить все твики к значениям по умолчанию", "reset_toggles", false, true));
        pages.push_back(std::move(p));
    }

    // -------------------------------------------------------------------- logs
    {
        Page p;
        p.id = "logs";
        p.title = L"Логи";
        p.subtitle = L"Полный журнал сессии и файл для диагностики";
        p.has_apply = false;
        p.rows.push_back(info("file", L"Файл журнала", fsx::log_dir().wstring()));
        p.rows.push_back(note("hint", L"Журнал хранит последние 4000 записей; при 2 МБ файл пересоздаётся."));
        p.rows.push_back(button("open", L"Открыть папку логов", "open_logs", false));
        p.rows.push_back(button("clear", L"Очистить журнал в окне", "clear_logs", false));
        pages.push_back(std::move(p));
    }

    return pages;
}

}  // namespace ro::ui
