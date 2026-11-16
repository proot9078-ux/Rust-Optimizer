#include "ro/json.hpp"

#include <fstream>

#include "ro/fs.hpp"
#include "ro/log.hpp"
#include "ro/str.hpp"

namespace ro::json {

std::optional<Value> parse(std::string_view text, std::string* error) {
    Value v = Value::parse(text.begin(), text.end(), nullptr, false);
    if (v.is_discarded()) {
        if (error) *error = "invalid JSON";
        return std::nullopt;
    }
    if (error) error->clear();
    return v;
}

std::optional<Value> parse_file(const std::filesystem::path& path, std::string* error) {
    const auto text = fsx::read_text(path);
    if (!text) {
        if (error) *error = "cannot read file";
        return std::nullopt;
    }
    return parse(*text, error);
}

std::string dump(const Value& v, bool pretty) { return v.dump(pretty ? 2 : -1); }

bool save_file(const std::filesystem::path& path, const Value& v) {
    return fsx::write_text_atomic(path, dump(v, true) + "\n");
}

std::string get_string(const Value& v, const char* key, std::string fallback) {
    const auto it = v.find(key);
    if (it == v.end() || !it->is_string()) return fallback;
    return it->get<std::string>();
}

bool get_bool(const Value& v, const char* key, bool fallback) {
    const auto it = v.find(key);
    if (it == v.end() || !it->is_boolean()) return fallback;
    return it->get<bool>();
}

long long get_int(const Value& v, const char* key, long long fallback) {
    const auto it = v.find(key);
    if (it == v.end()) return fallback;
    if (it->is_number_integer()) return it->get<long long>();
    if (it->is_number_float()) return static_cast<long long>(it->get<double>());
    if (it->is_string()) {
        const auto n = str::to_int(it->get<std::string>());
        if (n) return *n;
    }
    return fallback;
}

double get_number(const Value& v, const char* key, double fallback) {
    const auto it = v.find(key);
    if (it == v.end() || !it->is_number()) return fallback;
    return it->get<double>();
}

}  // namespace ro::json
