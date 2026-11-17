#include "ro/diagnostics.hpp"

#include <algorithm>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/version.hpp"

namespace ro::diag {

namespace fs = std::filesystem;

namespace {

std::string line(const std::string& key, const std::wstring& value) {
    return key + ": " + str::narrow(value) + "\r\n";
}

}  // namespace

fs::path reports_dir() { return fsx::data_dir() / L"reports"; }

fs::path write_report(const HardwareInfo& hw, const AppSettings& settings, const std::wstring& rust_dir,
                      const std::wstring& fortnite_dir, std::string& error) {
    std::string text;
    text += "Rust Optimizer " + std::string(kVersion) + " - диагностический отчёт\r\n";
    text += "Создан: " + fsx::time_stamp() + "\r\n\r\n";

    text += "=== СИСТЕМА ===\r\n";
    text += line("ОС", hw.os_display.empty() ? hw.os : hw.os_display);
    text += line("Процессор", hw.cpu_name);
    text += "Ядра: " + std::to_string(hw.physical_cores) + " физических / " +
            std::to_string(hw.logical_cores) + " логических\r\n";
    text += "ОЗУ: " + str::human_bytes(hw.ram_bytes) + "\r\n";
    text += line("Видеокарта", hw.gpu.name);
    text += "VRAM: " + str::human_bytes(hw.gpu.vram_bytes) + "\r\n";
    text += std::string("HAGS: ") + (hw.hags_enabled ? "вкл" : "выкл");
    if (!hw.hags_supported) text += " (не поддерживается)";
    else if (hw.hags_reboot_pending) text += " (нужна перезагрузка)";
    text += "\r\nGame DVR: ";
    text += hw.game_dvr_enabled ? "вкл" : "выкл";
    text += " | Game Mode: ";
    text += hw.game_mode_enabled ? "вкл" : "выкл";
    text += "\r\n\r\n";

    text += "=== ИГРЫ ===\r\n";
    text += line("RUST", rust_dir.empty() ? L"не найден" : rust_dir);
    text += line("FORTNITE", fortnite_dir.empty() ? L"не найден" : fortnite_dir);
    text += "\r\n";

    text += "=== НАСТРОЙКИ ===\r\n";
    text += line("Тема", str::widen(settings.theme));
    text += std::string("Автоприоритет: ") + (settings.auto_priority ? "вкл" : "выкл") + "\r\n";
    text += std::string("Сворачивать после применения: ") + (settings.minimize_on_apply ? "вкл" : "выкл") +
            "\r\n";
    text += std::string("Affinity разрешён: ") + (settings.allow_affinity ? "да" : "нет") + "\r\n\r\n";

    text += "=== ЖУРНАЛ (последние записи) ===\r\n";
    const auto records = log::Logger::instance().tail(120);
    for (const auto& record : records) {
        const char* level = "INFO";
        switch (record.level) {
            case log::Level::Warn: level = "WARN"; break;
            case log::Level::Error: level = "ERROR"; break;
            case log::Level::Success: level = "OK"; break;
            case log::Level::Debug: level = "DEBUG"; break;
            default: break;
        }
        text += record.time + "  [" + level + "] " + record.text + "\r\n";
    }

    fsx::ensure_dir(reports_dir());
    const fs::path file = reports_dir() / (L"report-" + str::widen(fsx::time_stamp()) + L".txt");
    if (!fsx::write_text(file, text)) {
        error = "Не удалось записать отчёт в " + str::narrow(file.wstring());
        return {};
    }
    log::success("diagnostics: report saved to " + str::narrow(file.wstring()));
    return file;
}

}  // namespace ro::diag
