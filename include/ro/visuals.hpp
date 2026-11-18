#pragma once
#include <string>
#include <string_view>
#include <vector>

// Picture quality helpers.
//
// The only mechanism used here is the documented GDI gamma ramp
// (GetDeviceGammaRamp / SetDeviceGammaRamp): no injection, no hooks, no
// overlays. Original ramps are stored on disk before the first change, so
// "Выключить" returns the desktop to exactly the state it was in, even after a
// restart. The app also offers a shortcut to NVIDIA's own panel, because the
// driver-side settings (Digital Vibrance, texture filtering) can only be set
// there.
namespace ro::visuals {

struct Preset {
    std::string id;          // off / soft / vivid / cinema
    std::wstring title;
    std::wstring desc;
};

const std::vector<Preset>& presets();

// Applies a preset to every attached display. "off" restores the originals.
// Returns false with `error` when no display accepted the ramp (some drivers
// refuse non-linear ramps) or when saving the originals failed.
bool apply(std::string_view id, std::string& error);

// Restores the saved original ramps (uses the saved data, not the current
// screen state, so repeated calls are safe).
bool restore(std::string& error);

bool has_saved();

bool nvidia_installed();
// Opens the NVIDIA Control Panel / NVIDIA app. Returns false when no known
// executable is present.
bool open_nvidia_panel(std::string& error);

}  // namespace ro::visuals
