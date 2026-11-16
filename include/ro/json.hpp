#pragma once
// Small JSON facade: the only translation unit that includes nlohmann keeps the
// compile time of the rest of the project low.
#include <filesystem>
#include <optional>
#include <string>

#include <nlohmann/json.hpp>

namespace ro::json {

using Value = nlohmann::json;

std::optional<Value> parse(std::string_view text, std::string* error = nullptr);
std::optional<Value> parse_file(const std::filesystem::path& path, std::string* error = nullptr);
std::string dump(const Value& v, bool pretty = true);
bool save_file(const std::filesystem::path& path, const Value& v);

std::string get_string(const Value& v, const char* key, std::string fallback = {});
bool get_bool(const Value& v, const char* key, bool fallback = false);
long long get_int(const Value& v, const char* key, long long fallback = 0);
double get_number(const Value& v, const char* key, double fallback = 0.0);

}  // namespace ro::json
