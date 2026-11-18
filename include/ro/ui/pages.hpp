#pragma once
#include <map>
#include <string>
#include <vector>

#include "ro/affinity.hpp"
#include "ro/fortnite_tweaks.hpp"
#include "ro/hardware.hpp"
#include "ro/rust_tweaks.hpp"
#include "ro/settings.hpp"

namespace ro::ui {

enum class RowKind { Section, Toggle, Info, Button, Note, Spacer };

struct Row {
    RowKind kind = RowKind::Info;
    std::string id;
    std::wstring title;
    std::wstring desc;
    std::string action;      // for Button rows
    bool on = false;         // Toggle state / Info highlight
    bool danger = false;
    bool primary = false;
    bool enabled = true;
};

struct Page {
    std::string id;
    std::wstring title;
    std::wstring subtitle;
    std::vector<Row> rows;
    std::wstring apply_label = L"Применить";
    bool has_apply = true;
};

struct PageContext {
    const AppSettings* settings = nullptr;
    const HardwareInfo* hw = nullptr;
    const cpu::Topology* cpu = nullptr;
    const GameInstall* rust = nullptr;
    const GameInstall* fortnite = nullptr;
    const std::map<std::string, bool>* toggles = nullptr;
    bool admin = false;
    bool update_available = false;
    std::string latest_version;
    std::string theme_id = "dark";
    std::string image_preset = "off";
    std::wstring steam_dir;
};

std::vector<Page> build_pages(const PageContext& ctx);

// Default toggle values (used when the settings file has no entry yet).
std::map<std::string, bool> default_toggles();
std::string toggle_key(const std::string& page_id, const std::string& row_id);

}  // namespace ro::ui
