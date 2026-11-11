# 重建 filmlab-host.exe（支持 Nikon Z50II / Z5II 的 HE、HE* NEF）
#
# 这个脚本复现了本次修复的构建过程。它只重建 host，不动 Tauri 外壳：
# 「胶片模拟 3.0.exe」只是通过 IPC 找同目录的 filmlab-host.exe，所以换掉这个
# 文件就够了。
#
# 前置条件（全部需要在 PATH 上）：
#   gcc / g++      MinGW-w64，>= 15（本次用 MSYS2 UCRT64 的 GCC 16.2 验证）
#   cmake          >= 3.20
#   ninja
#   glslangValidator   Vulkan SDK 或 MSYS2 的 glslang 包
#   python         >= 3.12（跑 setup-input-codecs.py / setup-lens-codecs.py）
#   meson          1.9.x（GLib 用；pip install meson==1.9.2）
#
# 依赖会被下载到 -DependencyDirectory，源码树在 -SourceDirectory。
[CmdletBinding()]
param(
    [string]$SourceDirectory = (Split-Path $PSScriptRoot -Parent),
    [string]$DependencyDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build-z50ii\deps'),
    [string]$BuildDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build-z50ii\build'),
    [string]$AppDirectory,
    [int]$Jobs = 8
)

$ErrorActionPreference = 'Stop'
$SourceDirectory = [IO.Path]::GetFullPath($SourceDirectory)
$DependencyDirectory = [IO.Path]::GetFullPath($DependencyDirectory)
$BuildDirectory = [IO.Path]::GetFullPath($BuildDirectory)

foreach ($tool in @('cmake', 'gcc', 'g++', 'ninja', 'glslangValidator', 'python')) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        throw "$tool is not on PATH; see the header of this script for the toolchain it expects."
    }
}
if (-not (Get-Command meson -ErrorAction SilentlyContinue)) {
    throw 'meson is not on PATH; the GLib build needs it (pip install meson==1.9.2).'
}

Write-Host "[1/5] LibRaw 0.23.0 snapshot" -ForegroundColor Cyan
& (Join-Path $SourceDirectory 'engine\setup-libraw.ps1') -DependencyDirectory $DependencyDirectory

Write-Host "[2/5] export codecs (libjpeg-turbo, libpng, zlib-ng, nasm)" -ForegroundColor Cyan
& (Join-Path $SourceDirectory 'engine\setup-codecs.ps1') -DependencyDirectory (Join-Path $DependencyDirectory 'export-codecs')

Write-Host "[3/5] input codecs (lcms2, OpenEXR, libheif)" -ForegroundColor Cyan
& python (Join-Path $SourceDirectory 'engine\setup-input-codecs.py') `
    --sources (Join-Path $DependencyDirectory 'input-codecs\src') `
    --build (Join-Path $DependencyDirectory 'input-codecs\build') `
    --install (Join-Path $DependencyDirectory 'input-codecs\install') `
    --cmake cmake --generator Ninja --cc gcc --cxx g++ --jobs $Jobs

Write-Host "[4/5] lens codecs (Lensfun, GLib, pcre2, libffi)" -ForegroundColor Cyan
& python (Join-Path $SourceDirectory 'engine\setup-lens-codecs.py') `
    --sources (Join-Path $DependencyDirectory 'lens-codecs\src') `
    --build (Join-Path $DependencyDirectory 'lens-codecs\build') `
    --install (Join-Path $DependencyDirectory 'lens-codecs\install') `
    --cmake cmake --generator Ninja --cc gcc --cxx g++ --jobs $Jobs

Write-Host "[5/5] filmlab-host" -ForegroundColor Cyan
& cmake -S $SourceDirectory -B $BuildDirectory -G Ninja `
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER=gcc -DCMAKE_CXX_COMPILER=g++ `
    '-DSPEKTRALAB_BUILD_NATIVE_RAW=ON' '-DSPEKTRALAB_BUILD_HOST=ON' '-DSPEKTRALAB_BUILD_DESKTOP=OFF' `
    '-DSPEKTRALAB_REQUIRE_VULKAN=ON' '-DBUILD_TESTING=OFF' `
    "-DSPEKTRALAB_DEPS_DIR=$($DependencyDirectory.Replace('\', '/'))" `
    "-DSPEKTRALAB_LIBRAW_SOURCE=$((Join-Path $DependencyDirectory 'LibRaw-0.23.0').Replace('\', '/'))" `
    "-DSPEKTRALAB_CODECS_DIR=$((Join-Path $DependencyDirectory 'export-codecs').Replace('\', '/'))" `
    "-DSPEKTRALAB_INPUT_CODEC_PREFIX=$((Join-Path $DependencyDirectory 'input-codecs\install').Replace('\', '/'))" `
    "-DSPEKTRALAB_LENS_PREFIX=$((Join-Path $DependencyDirectory 'lens-codecs\install').Replace('\', '/'))"
if ($LASTEXITCODE) { throw 'cmake configure failed' }

& cmake --build $BuildDirectory --target filmlab-host -j $Jobs
if ($LASTEXITCODE) { throw 'cmake build failed' }

$exe = Join-Path $BuildDirectory 'engine\host\filmlab-host.exe'
if (-not (Test-Path $exe)) { throw "build produced no host at $exe" }
Write-Host "built: $exe" -ForegroundColor Green

if ($AppDirectory) {
    if (-not (Test-Path (Join-Path $AppDirectory '胶片模拟 3.0.exe'))) {
        throw "-AppDirectory does not look like the portable app folder: $AppDirectory"
    }
    Copy-Item $exe (Join-Path $AppDirectory 'filmlab-host.exe') -Force
    # The host links the MinGW runtime dynamically; ship the ones it was built against.
    foreach ($dll in @('libgcc_s_seh-1.dll', 'libstdc++-6.dll', 'libgomp-1.dll', 'libwinpthread-1.dll')) {
        $found = Get-Command $dll -ErrorAction SilentlyContinue
        if ($found) { Copy-Item $found.Source (Join-Path $AppDirectory $dll) -Force }
    }
    Write-Host "installed into $AppDirectory" -ForegroundColor Green
}
