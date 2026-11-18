#include "ro/visuals.hpp"

#include <windows.h>

#include <algorithm>
#include <array>
#include <cmath>
#include <filesystem>
#include <vector>

#include "ro/fs.hpp"
#include "ro/json.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"
#include "ro/win32.hpp"

namespace ro::visuals {

namespace {

constexpr int kRampEntries = 256 * 3;

struct Curve {
    double gamma = 1.0;
    double contrast = 1.0;
    double brightness = 0.0;
    double r = 1.0;
    double g = 1.0;
    double b = 1.0;
};

Curve curve_for(std::string_view id) {
    Curve c;
    if (id == "soft") {
        c.gamma = 0.98;
        c.contrast = 1.06;
        c.brightness = 0.005;
        c.r = 1.02;
        c.b = 0.99;
    } else if (id == "vivid") {
        c.gamma = 0.90;
        c.contrast = 1.16;
        c.brightness = 0.010;
        c.r = 1.05;
        c.b = 0.97;
    } else if (id == "cinema") {
        c.gamma = 0.95;
        c.contrast = 1.10;
        c.r = 1.03;
        c.b = 0.96;
    }
    return c;
}

using Ramp = std::array<WORD, kRampEntries>;

std::filesystem::path ramp_file() {
    return fsx::data_dir() / L"display-ramps.json";
}

std::vector<std::wstring> displays() {
    std::vector<std::wstring> out;
    for (DWORD i = 0;; ++i) {
        DISPLAY_DEVICEW dd{};
        dd.cb = sizeof(dd);
        if (!::EnumDisplayDevicesW(nullptr, i, &dd, 0)) break;
        if ((dd.StateFlags & DISPLAY_DEVICE_ATTACHED_TO_DESKTOP) == 0) continue;
        out.emplace_back(dd.DeviceName);
    }
    return out;
}

bool read_ramp(const std::wstring& device, Ramp& ramp) {
    HDC dc = ::CreateDCW(device.c_str(), nullptr, nullptr, nullptr);
    if (!dc) return false;
    const BOOL ok = ::GetDeviceGammaRamp(dc, ramp.data());
    ::DeleteDC(dc);
    return ok != FALSE;
}

bool write_ramp(const std::wstring& device, const Ramp& ramp) {
    HDC dc = ::CreateDCW(device.c_str(), nullptr, nullptr, nullptr);
    if (!dc) return false;
    const BOOL ok = ::SetDeviceGammaRamp(dc, const_cast<WORD*>(ramp.data()));
    ::DeleteDC(dc);
    return ok != FALSE;
}

void build_ramp(const Ramp* source, const Curve& c, Ramp& out) {
    for (int ch = 0; ch < 3; ++ch) {
        const double mul = ch == 0 ? c.r : (ch == 2 ? c.b : c.g);
        for (int i = 0; i < 256; ++i) {
            double x = source ? (*source)[static_cast<std::size_t>(ch * 256 + i)] / 65535.0 : i / 255.0;
            x = std::clamp(x, 0.0, 1.0);
            double y = std::pow(x, c.gamma);
            y = 0.5 + (y - 0.5) * c.contrast + c.brightness;
            y = std::clamp(y * mul, 0.0, 1.0);
            out[static_cast<std::size_t>(ch * 256 + i)] = static_cast<WORD>(std::lround(y * 65535.0));
        }
    }
}

bool save_originals(std::string& error) {
    json::Value root = json::Value::object();
    root["schema"] = 1;
    json::Value list = json::Value::array();
    for (const auto& device : displays()) {
        Ramp ramp{};
        if (!read_ramp(device, ramp)) continue;
        json::Value item = json::Value::object();
        item["device"] = str::narrow(device);
        json::Value arr = json::Value::array();
        for (const auto value : ramp) arr.push_back(static_cast<int>(value));
        item["ramp"] = std::move(arr);
        list.push_back(std::move(item));
    }
    if (list.empty()) {
        error = "не удалось прочитать гамму ни одного дисплея";
        return false;
    }
    root["displays"] = std::move(list);
    fsx::ensure_dir(ramp_file().parent_path());
    if (!json::save_file(ramp_file(), root)) {
        error = "не удалось сохранить исходную гамму";
        return false;
    }
    return true;
}

bool load_originals(std::vector<std::pair<std::wstring, Ramp>>& out) {
    out.clear();
    const auto j = json::parse_file(ramp_file());
    if (!j || !j->is_object()) return false;
    const auto it = j->find("displays");
    if (it == j->end() || !it->is_array()) return false;
    for (const auto& item : *it) {
        if (!item.is_object()) continue;
        const std::wstring device = str::widen(json::get_string(item, "device"));
        const auto ramp_it = item.find("ramp");
        if (device.empty() || ramp_it == item.end() || !ramp_it->is_array() ||
            ramp_it->size() != static_cast<std::size_t>(kRampEntries)) {
            continue;
        }
        Ramp ramp{};
        bool ok = true;
        for (std::size_t i = 0; i < ramp.size(); ++i) {
            if (!(*ramp_it)[i].is_number()) {
                ok = false;
                break;
            }
            ramp[i] = static_cast<WORD>((*ramp_it)[i].get<int>());
        }
        if (ok) out.emplace_back(device, ramp);
    }
    return !out.empty();
}

}  // namespace

const std::vector<Preset>& presets() {
    static const std::vector<Preset> list = {
        {"off", L"Как в Windows", L"Вернуть исходную гамму и цвета монитора."},
        {"soft", L"Мягко", L"Чуть больше контраста и насыщенности — без пересветов."},
        {"vivid", L"СОЧНО (как у блогеров)", L"Контраст и цвет «как на ютубе»: ярче, глубже, теплее. "
                                            L"Гамма-правка экрана, не трогает игру."},
        {"cinema", L"Кино", L"Тёплый оттенок и мягкий контраст для спокойной картинки."},
    };
    return list;
}

bool has_saved() { return fsx::is_regular_file(ramp_file()); }

bool apply(std::string_view id, std::string& error) {
    if (id.empty() || id == "off") {
        // Nothing was ever changed on this machine: "off" is already true.
        if (!has_saved()) return true;
        return restore(error);
    }

    std::vector<std::pair<std::wstring, Ramp>> originals;
    if (!load_originals(originals)) {
        if (!save_originals(error)) return false;
        if (!load_originals(originals)) {
            error = "исходная гамма не сохранилась";
            return false;
        }
    }

    const Curve curve = curve_for(id);
    int applied = 0;
    for (const auto& [device, original] : originals) {
        // Only touch displays that are still attached.
        Ramp current{};
        if (!read_ramp(device, current)) continue;
        Ramp next{};
        build_ramp(&original, curve, next);
        if (write_ramp(device, next)) {
            ++applied;
        } else {
            log::warn("visuals: driver rejected the gamma ramp for " + str::narrow(device));
        }
    }
    if (applied == 0) {
        error = "драйвер отклонил настройку гаммы (нужен активный монитор)";
        return false;
    }
    log::success("visuals: preset \"" + std::string(id) + "\" applied to " + std::to_string(applied) + " display(s)");
    return true;
}

bool restore(std::string& error) {
    std::vector<std::pair<std::wstring, Ramp>> originals;
    if (!load_originals(originals)) {
        error = "сохранённая гамма не найдена";
        return false;
    }
    int restored = 0;
    for (const auto& [device, ramp] : originals) {
        if (write_ramp(device, ramp)) ++restored;
    }
    if (restored == 0) {
        error = "не удалось вернуть исходную гамму";
        return false;
    }
    log::success("visuals: original gamma restored on " + std::to_string(restored) + " display(s)");
    return true;
}

bool nvidia_installed() {
    const std::wstring candidates[] = {
        L"C:\\Program Files\\NVIDIA Corporation\\Control Panel Client\\nvcplui.exe",
        L"C:\\Program Files (x86)\\NVIDIA Corporation\\Control Panel Client\\nvcplui.exe",
        L"C:\\Program Files\\NVIDIA Corporation\\NVIDIA app\\CEF\\NVIDIA app.exe",
        L"C:\\Program Files\\NVIDIA Corporation\\NVIDIA app\\NVIDIA app.exe",
        L"C:\\Windows\\System32\\nvcplui.exe",
    };
    for (const auto& path : candidates) {
        if (fsx::is_regular_file(path)) return true;
    }
    return false;
}

bool open_nvidia_panel(std::string& error) {
    const std::wstring candidates[] = {
        L"C:\\Program Files\\NVIDIA Corporation\\NVIDIA app\\CEF\\NVIDIA app.exe",
        L"C:\\Program Files\\NVIDIA Corporation\\NVIDIA app\\NVIDIA app.exe",
        L"C:\\Program Files\\NVIDIA Corporation\\Control Panel Client\\nvcplui.exe",
        L"C:\\Program Files (x86)\\NVIDIA Corporation\\Control Panel Client\\nvcplui.exe",
        L"C:\\Windows\\System32\\nvcplui.exe",
    };
    for (const auto& path : candidates) {
        if (!fsx::is_regular_file(path)) continue;
        if (win::shell_open(path)) {
            log::info("visuals: opened NVIDIA panel: " + str::narrow(path));
            return true;
        }
    }
    error = "Панель NVIDIA не найдена — установите драйвер NVIDIA или приложение NVIDIA app";
    return false;
}

}  // namespace ro::visuals
