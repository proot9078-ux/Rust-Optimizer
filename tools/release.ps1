#Requires -Version 5.1
<#
.SYNOPSIS
    Builds the Release executable, packs the distribution zip, writes SHA256SUMS
    and publishes a GitHub release with the GitHub CLI (gh).

.DESCRIPTION
    Requires: Visual Studio 2022 (C++ workload), CMake 3.21+, GitHub CLI
    authenticated with `gh auth login` and permission to write releases in
    proot9078-ux/Rust-Optimizer.

.EXAMPLE
    pwsh ./tools/release.ps1 -Version 8.0.1
#>
[CmdletBinding()]
param(
    [string]$Version,
    [string]$Repo = "proot9078-ux/Rust-Optimizer",
    [string]$Notes,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
Push-Location $root
try {
    if (-not $Version) {
        $line = Select-String -Path "CMakeLists.txt" -Pattern '^\s*VERSION\s+([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
        if (-not $line) { throw "Cannot read the project version from CMakeLists.txt" }
        $Version = $line.Matches[0].Groups[1].Value
    }
    $tag = "v$Version"
    Write-Host "==> Building Rust Optimizer $Version" -ForegroundColor Cyan

    $build = Join-Path $root "build-release"
    cmake -S . -B $build -G "Visual Studio 17 2022" -A x64 -DRO_BUILD_TESTS=ON -DRO_WARNINGS_AS_ERRORS=ON
    if ($LASTEXITCODE -ne 0) { throw "CMake configure failed" }
    cmake --build $build --config Release --parallel
    if ($LASTEXITCODE -ne 0) { throw "Build failed" }
    ctest --test-dir $build -C Release --output-on-failure
    if ($LASTEXITCODE -ne 0) { throw "Tests failed" }

    $exe = Join-Path $build "Release\RustOptimizer.exe"
    if (-not (Test-Path $exe)) { throw "Executable not found: $exe" }

    # Smoke-test the produced binary before publishing it.
    & $exe --version
    if ($LASTEXITCODE -ne 0) { throw "--version failed" }

    Write-Host "==> Packaging" -ForegroundColor Cyan
    $stage = Join-Path $root "dist\stage"
    if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Copy-Item $exe $stage
    Copy-Item README.md, LICENSE, CHANGELOG.md $stage
    $zip = Join-Path $root "dist\RustOptimizer-win64-$Version.zip"
    New-Item -ItemType Directory -Force -Path (Split-Path $zip) | Out-Null
    Compress-Archive -Path (Join-Path $stage "*") -DestinationPath $zip -Force

    $hash = (Get-FileHash -Algorithm SHA256 $zip).Hash.ToLower()
    $sums = Join-Path $root "dist\SHA256SUMS.txt"
    "$hash  $(Split-Path -Leaf $zip)" | Set-Content -Encoding ascii $sums
    Write-Host "SHA256: $hash"

    if ($DryRun) {
        Write-Host "Dry run: release $tag not published. Artifacts in dist\." -ForegroundColor Yellow
        return
    }

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
        throw "GitHub CLI (gh) is not installed or not on PATH"
    }
    gh auth status | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "gh is not authenticated (run: gh auth login)" }

    if (-not $Notes) {
        $Notes = "Rust Optimizer $Version. See CHANGELOG.md for details."
    }
    Write-Host "==> Publishing $tag to $Repo" -ForegroundColor Cyan
    gh release create $tag $zip (Join-Path $build "Release\RustOptimizer.exe") $sums `
        --repo $Repo --title "Rust Optimizer $Version" --notes $Notes
    if ($LASTEXITCODE -ne 0) { throw "gh release create failed" }
    Write-Host "==> Done: https://github.com/$Repo/releases/tag/$tag" -ForegroundColor Green
}
finally {
    Pop-Location
}
