#include "ro/ui/theme.hpp"

namespace ro::ui {

Themed dark() {
    Themed t;
    t.dark = true;
    t.bg = rgb(0x0B0910);
    t.sidebar = rgb(0x120E1B);
    t.card = rgb(0x181224);
    t.card_hover = rgb(0x1F1830);
    t.border = rgb(0x2C2340);
    t.text = rgb(0xF3EEFF);
    t.text_dim = rgb(0xB4A9CC);
    t.text_muted = rgb(0x7C7196);
    t.accent = rgb(0x8B5CF6);
    t.accent_soft = rgb(0x8B5CF6, 0.16f);
    t.accent_text = rgb(0xFFFFFF);
    t.ok = rgb(0x4ADE80);
    t.warn = rgb(0xFBBF24);
    t.err = rgb(0xF87171);
    t.toggle_off = rgb(0x2E2640);
    return t;
}

Themed light() {
    Themed t;
    t.dark = false;
    t.bg = rgb(0xF6F4FB);
    t.sidebar = rgb(0xFFFFFF);
    t.card = rgb(0xFFFFFF);
    t.card_hover = rgb(0xF2EDFF);
    t.border = rgb(0xE2DAF2);
    t.text = rgb(0x1B1428);
    t.text_dim = rgb(0x5B5170);
    t.text_muted = rgb(0x8B82A0);
    t.accent = rgb(0x6D28D9);
    t.accent_soft = rgb(0x6D28D9, 0.12f);
    t.accent_text = rgb(0xFFFFFF);
    t.ok = rgb(0x15803D);
    t.warn = rgb(0xB45309);
    t.err = rgb(0xB91C1C);
    t.toggle_off = rgb(0xDDD6EC);
    return t;
}

namespace {

Themed midnight() {
    Themed t;
    t.dark = true;
    t.bg = rgb(0x070B14);
    t.sidebar = rgb(0x0A1220);
    t.card = rgb(0x101A2B);
    t.card_hover = rgb(0x16233A);
    t.border = rgb(0x1E2E4A);
    t.text = rgb(0xEDF4FF);
    t.text_dim = rgb(0xA9BDDA);
    t.text_muted = rgb(0x6C82A6);
    t.accent = rgb(0x3B82F6);
    t.accent_soft = rgb(0x3B82F6, 0.18f);
    t.accent_text = rgb(0xFFFFFF);
    t.ok = rgb(0x34D399);
    t.warn = rgb(0xFBBF24);
    t.err = rgb(0xF87171);
    t.toggle_off = rgb(0x1B2942);
    return t;
}

Themed neon() {
    Themed t;
    t.dark = true;
    t.bg = rgb(0x05070A);
    t.sidebar = rgb(0x0A0E13);
    t.card = rgb(0x10161D);
    t.card_hover = rgb(0x16202A);
    t.border = rgb(0x223039);
    t.text = rgb(0xE8FFF8);
    t.text_dim = rgb(0x9BC7BC);
    t.text_muted = rgb(0x63837B);
    t.accent = rgb(0x22D3EE);
    t.accent_soft = rgb(0x22D3EE, 0.18f);
    t.accent_text = rgb(0x041317);
    t.ok = rgb(0x4ADE80);
    t.warn = rgb(0xFDE047);
    t.err = rgb(0xFB7185);
    t.toggle_off = rgb(0x1B2A31);
    return t;
}

Themed rust() {
    Themed t;
    t.dark = true;
    t.bg = rgb(0x0F0A07);
    t.sidebar = rgb(0x171008);
    t.card = rgb(0x20160D);
    t.card_hover = rgb(0x2A1D11);
    t.border = rgb(0x3A2817);
    t.text = rgb(0xFFF2E4);
    t.text_dim = rgb(0xD8B79A);
    t.text_muted = rgb(0x9A7B5D);
    t.accent = rgb(0xFF7A1A);
    t.accent_soft = rgb(0xFF7A1A, 0.18f);
    t.accent_text = rgb(0x1A0D03);
    t.ok = rgb(0x84CC16);
    t.warn = rgb(0xFDBA74);
    t.err = rgb(0xEF4444);
    t.toggle_off = rgb(0x352414);
    return t;
}

Themed ocean() {
    Themed t;
    t.dark = true;
    t.bg = rgb(0x071013);
    t.sidebar = rgb(0x0B181C);
    t.card = rgb(0x102227);
    t.card_hover = rgb(0x163138);
    t.border = rgb(0x1D4049);
    t.text = rgb(0xE6FBFF);
    t.text_dim = rgb(0x9FC9D1);
    t.text_muted = rgb(0x6A8F97);
    t.accent = rgb(0x14B8A6);
    t.accent_soft = rgb(0x14B8A6, 0.18f);
    t.accent_text = rgb(0x03191A);
    t.ok = rgb(0x4ADE80);
    t.warn = rgb(0xFBBF24);
    t.err = rgb(0xFB7185);
    t.toggle_off = rgb(0x193A41);
    return t;
}

}  // namespace

Themed for_mode(bool dark_mode) { return dark_mode ? dark() : light(); }

Themed preset(std::string_view id) {
    if (id == "light") return light();
    if (id == "midnight") return midnight();
    if (id == "neon") return neon();
    if (id == "rust") return rust();
    if (id == "ocean") return ocean();
    return dark();
}

const std::vector<std::string>& theme_ids() {
    static const std::vector<std::string> ids = {"dark", "midnight", "light", "neon", "rust", "ocean"};
    return ids;
}

const wchar_t* theme_title(std::string_view id) {
    if (id == "light") return L"Светлая";
    if (id == "midnight") return L"Полночь";
    if (id == "neon") return L"Неон";
    if (id == "rust") return L"RUST";
    if (id == "ocean") return L"Океан";
    return L"Тёмная";
}

std::string normalise_theme(std::string_view id) {
    for (const auto& known : theme_ids()) {
        if (known == id) return known;
    }
    return "dark";
}

}  // namespace ro::ui
