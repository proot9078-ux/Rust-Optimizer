#pragma once
#include <d2d1.h>
#include <dwrite.h>

#include <string>

namespace ro::ui {

struct Themed {
    D2D1_COLOR_F bg;
    D2D1_COLOR_F sidebar;
    D2D1_COLOR_F card;
    D2D1_COLOR_F card_hover;
    D2D1_COLOR_F border;
    D2D1_COLOR_F text;
    D2D1_COLOR_F text_dim;
    D2D1_COLOR_F text_muted;
    D2D1_COLOR_F accent;
    D2D1_COLOR_F accent_soft;
    D2D1_COLOR_F accent_text;
    D2D1_COLOR_F ok;
    D2D1_COLOR_F warn;
    D2D1_COLOR_F err;
    D2D1_COLOR_F toggle_off;
    bool dark = true;
};

inline D2D1_COLOR_F rgb(unsigned rgb_value, float alpha = 1.0f) {
    return D2D1::ColorF(((rgb_value >> 16) & 0xFF) / 255.0f, ((rgb_value >> 8) & 0xFF) / 255.0f,
                        (rgb_value & 0xFF) / 255.0f, alpha);
}

Themed dark();
Themed light();
Themed for_mode(bool dark_mode);

}  // namespace ro::ui
