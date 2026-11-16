#pragma once
// Central application identity. Version comes from CMake (RO_VERSION).
#ifndef RO_VERSION
#define RO_VERSION "8.0.0"
#endif
#ifndef RO_GITHUB_OWNER
#define RO_GITHUB_OWNER "proot9078-ux"
#endif
#ifndef RO_GITHUB_REPO
#define RO_GITHUB_REPO "Rust-Optimizer"
#endif

namespace ro {
inline constexpr const char* kAppName = "Rust Optimizer";
inline constexpr const char* kAppId = "RustOptimizer";
inline constexpr const char* kVersion = RO_VERSION;
inline constexpr const char* kGithubOwner = RO_GITHUB_OWNER;
inline constexpr const char* kGithubRepo = RO_GITHUB_REPO;
inline constexpr const char* kUserAgent = "RustOptimizer/" RO_VERSION;
}  // namespace ro
