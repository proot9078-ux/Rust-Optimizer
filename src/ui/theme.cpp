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

Themed for_mode(bool dark_mode) { return dark_mode ? dark() : light(); }

}  // namespace ro::ui
