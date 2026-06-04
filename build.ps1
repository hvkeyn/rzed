<#
.SYNOPSIS
    Build Zed Editor and collect all files into a ready-to-run distribution folder.
.DESCRIPTION
    Checks for dependencies (Rust, VS Build Tools, CMake, Windows SDK),
    installs missing ones, builds binaries, and copies all runtime files
    into a separate dist/ folder with the proper hierarchy.
.PARAMETER Release
    Build release mode (default: debug).
.PARAMETER Arch
    Target architecture: x86_64 (default) or aarch64.
.PARAMETER SkipDeps
    Skip dependency checks and installation.
.PARAMETER SkipConpty
    Skip downloading conpty.dll and OpenConsole.exe.
.PARAMETER SkipAGS
    Skip downloading amd_ags_x64.dll.
.PARAMETER DistDir
    Output directory (default: .\dist).
#>

[CmdletBinding()]
Param(
    [switch]$Release,
    [ValidateSet("x86_64", "aarch64")]
    [string]$Arch = "x86_64",
    [switch]$SkipDeps,
    [switch]$SkipConpty,
    [switch]$SkipAGS,
    [string]$DistDir = ".\dist"
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$BuildProfile = if ($Release) { "release" } else { "debug" }
$Target = "$Arch-pc-windows-msvc"
$CargoOutDir = ".\target\$Target\$BuildProfile"

$CargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { "$env:USERPROFILE\.cargo" }
$CargoPath = "$CargoHome\bin\cargo.exe"
$RustupPath = "$CargoHome\bin\rustup.exe"

$ProjectRoot = (Get-Item $PSScriptRoot).FullName

# ============================================================================
# Step 1: Check and install dependencies
# ============================================================================

function Check-Dependencies {
    if ($SkipDeps) {
        Write-Host "[SKIP] Dependency check skipped (--SkipDeps)" -ForegroundColor Yellow
        return
    }

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Step 1: Check and Install Dependencies" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    # --- Rust ---
    Write-Host ""
    Write-Host "[1/5] Checking Rust..." -ForegroundColor White

    $hasCargoInPath = Get-Command cargo -ErrorAction SilentlyContinue
    $hasCargoOnDisk = Test-Path $CargoPath
    $needsRustInstall = (-not $hasCargoInPath) -and (-not $hasCargoOnDisk)

    if ($needsRustInstall) {
        Write-Host "  Rust not found. Installing rustup..." -ForegroundColor Yellow
        $rustupInit = "$env:TEMP\rustup-init.exe"
        $rustupUrl = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
        Invoke-WebRequest -Uri $rustupUrl -OutFile $rustupInit

        $installArgs = @("-y", "--default-toolchain", "1.95.0", "--profile", "minimal",
            "--component", "rustfmt", "--component", "clippy",
            "--component", "rust-analyzer", "--component", "rust-src")
        & $rustupInit @installArgs
        Remove-Item $rustupInit -Force

        $env:PATH = "$CargoHome\bin;$env:PATH"
        Write-Host "  Rust 1.95.0 installed." -ForegroundColor Green
    }
    else {
        if (-not $hasCargoInPath) {
            $env:PATH = "$CargoHome\bin;$env:PATH"
        }
        $cargoVersion = & cargo --version 2>$null
        Write-Host "  Rust found: $cargoVersion" -ForegroundColor Green
    }

    Write-Host "  Installing target $Target..."
    $output = (& rustup target add $Target 2>&1) -join ' '
    Write-Host "  $output" -ForegroundColor Gray

    # --- Visual Studio Build Tools ---
    Write-Host ""
    Write-Host "[2/5] Checking Visual Studio Build Tools..." -ForegroundColor White

    $programFilesX86 = ${env:ProgramFiles(x86)}
    $vsWherePath = "$programFilesX86\Microsoft Visual Studio\Installer\vswhere.exe"

    if (Test-Path $vsWherePath) {
        $vsPath = & $vsWherePath -latest -property installationPath 2>$null
        if ($vsPath) {
            Write-Host "  Visual Studio found: $vsPath" -ForegroundColor Green

            $vsDevShell = "$vsPath\Common7\Tools\Launch-VsDevShell.ps1"
            if (Test-Path $vsDevShell) {
                $vsArch = if ($Arch -eq "aarch64") { "arm64" } else { "amd64" }
                $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
                $hostArch = if ($osArch -eq "Arm64") { "arm64" } else { "amd64" }

                Write-Host "  Initializing VS Dev Shell (arch: $vsArch)..." -ForegroundColor Gray
                & $vsDevShell -Arch $vsArch -HostArch $hostArch
            }
        }
        else {
            Write-Host "  Visual Studio not found via vswhere." -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  vswhere.exe not found. You may need Visual Studio Build Tools." -ForegroundColor Yellow
        Write-Host "  Install 'Desktop development with C++' workload:" -ForegroundColor Yellow
        Write-Host "  https://visualstudio.microsoft.com/visual-cpp-build-tools/" -ForegroundColor Yellow
    }

    $hasCl = Get-Command cl.exe -ErrorAction SilentlyContinue
    if (-not $hasCl) {
        Write-Host "  [WARN] cl.exe not in PATH. MSVC toolchain is required for build." -ForegroundColor Yellow
    }
    else {
        Write-Host "  MSVC compiler found." -ForegroundColor Green
    }

    # --- Spectre-mitigated libs (optional; build works without them via patched crate) ---
    Write-Host ""
    Write-Host "[2b/5] Checking Spectre-mitigated MSVC libs..." -ForegroundColor White

    $spectreArch = if ($Arch -eq "aarch64") { "arm64" } else { "x64" }
    $spectreLibsPath = $null

    if ($hasCl) {
        $clPath = (Get-Command cl.exe).Source
        $spectreLibsPath = Join-Path (Split-Path $clPath -Parent) "..\..\..\..\lib\spectre\$spectreArch"
        $spectreLibsPath = [System.IO.Path]::GetFullPath($spectreLibsPath)
    }
    elseif (Test-Path $vsWherePath) {
        $vsPath = & $vsWherePath -latest -property installationPath 2>$null
        if ($vsPath) {
            $msvcRoot = Join-Path $vsPath "VC\Tools\MSVC"
            if (Test-Path $msvcRoot) {
                $msvcVer = Get-ChildItem $msvcRoot | Sort-Object Name -Descending | Select-Object -First 1
                if ($msvcVer) {
                    $spectreLibsPath = Join-Path $msvcVer.FullName "lib\spectre\$spectreArch"
                }
            }
        }
    }

    if ($spectreLibsPath -and (Test-Path $spectreLibsPath)) {
        Write-Host "  Spectre-mitigated libs found." -ForegroundColor Green
    }
    else {
        Write-Host "  [WARN] Spectre-mitigated libs not installed." -ForegroundColor Yellow
        Write-Host "  Local builds proceed with a patched msvc_spectre_libs (warning only)." -ForegroundColor Gray
        Write-Host "  For release/CI parity, add component in Visual Studio Installer:" -ForegroundColor Yellow
        Write-Host "    MSVC ... C++ x64/x86 Spectre-mitigated libs (latest)" -ForegroundColor Yellow
        Write-Host "    Component ID: Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre" -ForegroundColor Gray

        $vsInstaller = "$programFilesX86\Microsoft Visual Studio\Installer\setup.exe"
        if ((Test-Path $vsInstaller) -and $vsPath) {
            Write-Host "  Attempting quiet install of Spectre libs (may require elevation)..." -ForegroundColor Gray
            try {
                $modifyArgs = @(
                    "modify", "--installPath", $vsPath,
                    "--add", "Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre",
                    "--quiet", "--wait", "--norestart"
                )
                & $vsInstaller @modifyArgs 2>&1 | Out-Null
                if (Test-Path $spectreLibsPath) {
                    Write-Host "  Spectre-mitigated libs installed." -ForegroundColor Green
                }
            }
            catch {
                Write-Host "  [WARN] Could not install Spectre libs automatically." -ForegroundColor Yellow
            }
        }
    }

    # --- Windows SDK 10.0.26100 (WebRTC / livekit) ---
    Write-Host ""
    Write-Host "[3/5] Checking Windows SDK 10.0.26100..." -ForegroundColor White
    if (Test-WindowsSdk26100) {
        Write-Host "  Windows SDK 10.0.26100 found." -ForegroundColor Green
    }
    else {
        Write-Host "  Windows SDK 10.0.26100 not found (required for WebRTC)." -ForegroundColor Yellow
        if (-not $SkipDeps) {
            Install-WindowsSdk26100 | Out-Null
        }
        if (Test-WindowsSdk26100) {
            Write-Host "  Windows SDK 10.0.26100 installed." -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] Install: winget install -e --id Microsoft.WindowsSDK.10.0.26100" -ForegroundColor Yellow
        }
    }

    # --- CMake ---
    Write-Host ""
    Write-Host "[4/5] Checking CMake..." -ForegroundColor White

    $hasCmake = Get-Command cmake -ErrorAction SilentlyContinue
    if (-not $hasCmake) {
        Write-Host "  CMake not found. Trying winget..." -ForegroundColor Yellow
        try {
            winget install --id Kitware.CMake --silent --accept-package-agreements 2>$null
            $cmakeDir = "${env:ProgramFiles}\CMake\bin"
            if (Test-Path $cmakeDir) {
                $env:PATH = "$cmakeDir;$env:PATH"
            }
            Write-Host "  CMake installed." -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Could not install CMake via winget." -ForegroundColor Yellow
            Write-Host "  Download manually: https://cmake.org/download/" -ForegroundColor Yellow
        }
    }
    else {
        $cmakeVersion = & cmake --version 2>$null | Select-Object -First 1
        Write-Host "  CMake found: $cmakeVersion" -ForegroundColor Green
    }

    # --- Git ---
    Write-Host ""
    Write-Host "[5/5] Checking Git..." -ForegroundColor White

    $hasGit = Get-Command git -ErrorAction SilentlyContinue
    if (-not $hasGit) {
        Write-Host "  Git not found. Trying winget..." -ForegroundColor Yellow
        try {
            winget install --id Git.Git --silent --accept-package-agreements 2>$null
            $gitDir = "${env:ProgramFiles}\Git\bin"
            if (Test-Path $gitDir) {
                $env:PATH = "$gitDir;$env:PATH"
            }
            Write-Host "  Git installed." -ForegroundColor Green
        }
        catch {
            Write-Host "  [WARN] Could not install Git. Needed for ZED_COMMIT_SHA." -ForegroundColor Yellow
        }
    }
    else {
        $gitVersion = & git --version 2>$null
        Write-Host "  Git found: $gitVersion" -ForegroundColor Green
    }

    # --- LongPathsEnabled ---
    Write-Host ""
    Write-Host "[6/6] Checking LongPathsEnabled..." -ForegroundColor White
    try {
        $regPath = "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem"
        $longPaths = Get-ItemProperty -Path $regPath -Name "LongPathsEnabled" -ErrorAction Stop
        if ($longPaths.LongPathsEnabled -eq 1) {
            Write-Host "  LongPathsEnabled = 1 (OK)" -ForegroundColor Green
        }
        else {
            Write-Host "  LongPathsEnabled = 0; enabling..." -ForegroundColor Yellow
            Set-ItemProperty -Path $regPath -Name "LongPathsEnabled" -Value 1 -Type DWORD
            Write-Host "  LongPathsEnabled enabled. Reboot may be required." -ForegroundColor Green
        }
    }
    catch {
        Write-Host "  [WARN] Could not check LongPathsEnabled. Manual setup may be needed." -ForegroundColor Yellow
    }

    # --- git longpaths ---
    if ($hasGit) {
        & git config --global core.longpaths true 2>$null
    }

    Write-Host ""
    Write-Host "  Dependencies check complete." -ForegroundColor Cyan
}

# ============================================================================
# Step 2: Build binaries
# ============================================================================

function Initialize-MsvcEnvironment {
    $vsArch = if ($Arch -eq "aarch64") { "arm64" } else { "amd64" }
    $osArch = [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture
    $hostArch = if ($osArch -eq "Arm64") { "arm64" } else { "amd64" }

    $devShellCandidates = @(
        "C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1",
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\Launch-VsDevShell.ps1",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\Tools\Launch-VsDevShell.ps1",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\Common7\Tools\Launch-VsDevShell.ps1"
    )

    foreach ($devShell in $devShellCandidates) {
        if (Test-Path $devShell) {
            Write-Host "  Initializing MSVC environment ($devShell)..." -ForegroundColor Gray
            & $devShell -Arch $vsArch -HostArch $hostArch | Out-Null
            return
        }
    }

    Write-Host "  [WARN] Launch-VsDevShell.ps1 not found; relying on existing PATH." -ForegroundColor Yellow
}

function Test-WindowsSdk26100 {
    Test-Path "C:\Program Files (x86)\Windows Kits\10\Include\10.0.26100.0"
}

function Install-WindowsSdk26100 {
    Write-Host "  Installing Windows 11 SDK 10.0.26100 (required for WebRTC)..." -ForegroundColor Yellow
    try {
        winget install -e --id Microsoft.WindowsSDK.10.0.26100 `
            --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        return (Test-WindowsSdk26100)
    }
    catch {
        Write-Host "  [WARN] winget SDK install failed: $_" -ForegroundColor Yellow
        return $false
    }
}

function Build-Binaries {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Step 2: Building Zed (profile: $BuildProfile, target: $Target)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    if (-not (Test-WindowsSdk26100)) {
        Write-Host "  Windows SDK 10.0.26100 not found (WebRTC needs it)." -ForegroundColor Yellow
        if (-not (Install-WindowsSdk26100)) {
            Write-Host "  [WARN] Install manually: winget install -e --id Microsoft.WindowsSDK.10.0.26100" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "  Windows SDK 10.0.26100 found." -ForegroundColor Green
    }

    Initialize-MsvcEnvironment

    Push-Location $ProjectRoot

    try {
        # Main binaries: zed + cli + auto_update_helper
        Write-Host ""
        Write-Host "  Building zed + cli + auto_update_helper..."

        $mainArgs = @("build", "--package", "zed", "--package", "cli",
            "--package", "auto_update_helper", "--target", $Target)
        if ($Release) {
            $mainArgs = @("build", "--release", "--package", "zed", "--package", "cli",
                "--package", "auto_update_helper", "--target", $Target)
        }

        & cargo @mainArgs
        if ($LASTEXITCODE -ne 0) {
            throw "Build failed for zed/cli/auto_update_helper (exit code: $LASTEXITCODE)"
        }
        Write-Host "  rzed.exe, cli.exe, auto_update_helper.exe built." -ForegroundColor Green

        # explorer_command_injector.dll
        Write-Host ""
        Write-Host "  Building explorer_command_injector..."

        $injectorArgs = @("build", "--package", "explorer_command_injector", "--target", $Target)
        if ($Release) {
            $injectorArgs = @("build", "--release", "--package", "explorer_command_injector", "--target", $Target)
        }

        & cargo @injectorArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] explorer_command_injector.dll failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  explorer_command_injector.dll built." -ForegroundColor Green
        }

        # remote_server.exe
        Write-Host ""
        Write-Host "  Building remote_server..."

        $remoteArgs = @("build", "--package", "remote_server", "--target", $Target)
        if ($Release) {
            $remoteArgs = @("build", "--release", "--package", "remote_server", "--target", $Target)
        }

        & cargo @remoteArgs
        if ($LASTEXITCODE -ne 0) {
            Write-Host "  [WARN] remote_server.exe failed (exit code: $LASTEXITCODE)" -ForegroundColor Yellow
        }
        else {
            Write-Host "  remote_server.exe built." -ForegroundColor Green
        }
    }
    finally {
        Pop-Location
    }
}

# ============================================================================
# Step 3: Download external runtime dependencies
# ============================================================================

function Download-Conpty {
    Write-Host ""
    Write-Host "[ConPTY] Downloading ConPTY for terminal support..." -ForegroundColor White

    $conptyUrl = "https://github.com/microsoft/terminal/releases/download/v1.24.10621.0/Microsoft.Windows.Console.ConPTY.1.24.260303001.nupkg"
    $tempDir = "$env:TEMP\zed-conpty-build"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    $zipPath = "$tempDir\conpty.nupkg"

    try {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $conptyUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        # conpty.dll path differs by architecture
        if ($Arch -eq "aarch64") {
            $conptyDllSource = "$tempDir\runtimes\win-arm64\native\conpty.dll"
        }
        else {
            $conptyDllSource = "$tempDir\runtimes\win-x64\native\conpty.dll"
        }

        if (Test-Path $conptyDllSource) {
            $distTarget = Join-Path $DistDir "conpty.dll"
            Copy-Item -Path $conptyDllSource -Destination $distTarget -Force
            Write-Host "  conpty.dll -> dist\" -ForegroundColor Green

            # Also copy next to binary in target dir (same as build.rs does)
            $binaryDir = Join-Path $ProjectRoot "target\$Target\$BuildProfile"
            Copy-Item -Path $conptyDllSource -Destination "$binaryDir\conpty.dll" -Force
        }

        # OpenConsole.exe - copy both architectures if available
        $x64Source = "$tempDir\build\native\runtimes\x64\OpenConsole.exe"
        $arm64Source = "$tempDir\build\native\runtimes\arm64\OpenConsole.exe"

        if (Test-Path $x64Source) {
            $x64DistDir = Join-Path $DistDir "x64"
            New-Item -Path $x64DistDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path $x64Source -Destination "$x64DistDir\OpenConsole.exe" -Force
            Write-Host "  OpenConsole.exe (x64) -> dist\x64\" -ForegroundColor Green
        }

        if (Test-Path $arm64Source) {
            $arm64DistDir = Join-Path $DistDir "arm64"
            New-Item -Path $arm64DistDir -ItemType Directory -Force | Out-Null
            Copy-Item -Path $arm64Source -Destination "$arm64DistDir\OpenConsole.exe" -Force
            Write-Host "  OpenConsole.exe (arm64) -> dist\arm64\" -ForegroundColor Green
        }

        # Copy next to binary as well
        if (Test-Path $x64Source) {
            $binaryDir = Join-Path $ProjectRoot "target\$Target\$BuildProfile"
            Copy-Item -Path $x64Source -Destination "$binaryDir\OpenConsole.exe" -Force
        }

        Write-Host "  ConPTY download complete." -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Failed to download ConPTY: $_" -ForegroundColor Yellow
        Write-Host "  Terminal may not work correctly without ConPTY." -ForegroundColor Yellow
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Download-AGS {
    Write-Host ""
    Write-Host "[AGS] Downloading AMD GPU Services..." -ForegroundColor White

    if ($Arch -eq "aarch64") {
        Write-Host "  [SKIP] AMD AGS not needed for aarch64." -ForegroundColor Gray
        return
    }

    $agsUrl = "https://codeload.github.com/GPUOpen-LibrariesAndSDKs/AGS_SDK/zip/refs/tags/v6.3.0"
    $tempDir = "$env:TEMP\zed-ags-build"
    New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    $zipPath = "$tempDir\ags.zip"

    try {
        $ProgressPreference = "SilentlyContinue"
        Invoke-WebRequest -Uri $agsUrl -OutFile $zipPath
        Expand-Archive -Path $zipPath -DestinationPath $tempDir -Force

        $dllSource = "$tempDir\AGS_SDK-6.3.0\ags_lib\lib\amd_ags_x64.dll"
        if (Test-Path $dllSource) {
            $distTarget = Join-Path $DistDir "amd_ags_x64.dll"
            Copy-Item -Path $dllSource -Destination $distTarget -Force
            Write-Host "  amd_ags_x64.dll -> dist\" -ForegroundColor Green
        }
        else {
            Write-Host "  [WARN] amd_ags_x64.dll not found in downloaded archive." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Host "  [WARN] Failed to download AMD AGS: $_" -ForegroundColor Yellow
        Write-Host "  AMD GPU support may be limited." -ForegroundColor Yellow
    }
    finally {
        Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ============================================================================
# Step 4: Assemble distribution
# ============================================================================

function Assemble-Distribution {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Step 4: Assembling distribution in $DistDir" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    # Clean and create folders
    if (Test-Path $DistDir) {
        Remove-Item -Path $DistDir -Recurse -Force
    }
    New-Item -Path $DistDir -ItemType Directory -Force | Out-Null
    New-Item -Path "$DistDir\bin" -ItemType Directory -Force | Out-Null
    New-Item -Path "$DistDir\tools" -ItemType Directory -Force | Out-Null
    New-Item -Path "$DistDir\appx" -ItemType Directory -Force | Out-Null

    $srcDir = "$ProjectRoot\$CargoOutDir"

    # --- Main executable ---
    Write-Host ""
    Write-Host "  Copying binaries..." -ForegroundColor White
    Copy-Item -Path "$srcDir\rzed.exe" -Destination "$DistDir\RZed.exe" -Force
    $zedSize = (Get-Item "$DistDir\RZed.exe").Length
    $zedSizeMB = [math]::Round($zedSize / 1048576, 1)
    Write-Host "  rzed.exe -> dist\RZed.exe ($zedSizeMB MB)" -ForegroundColor Green

    # --- CLI ---
    if (Test-Path "$srcDir\cli.exe") {
        Copy-Item -Path "$srcDir\cli.exe" -Destination "$DistDir\bin\zed.exe" -Force
        Write-Host "  cli.exe -> dist\bin\zed.exe" -ForegroundColor Green
    }

    # --- WSL wrapper script ---
    $wslScript = "$ProjectRoot\crates\zed\resources\windows\zed.sh"
    if (Test-Path $wslScript) {
        Copy-Item -Path $wslScript -Destination "$DistDir\bin\zed" -Force
        Write-Host "  zed.sh -> dist\bin\zed" -ForegroundColor Green
    }

    # --- Auto update helper ---
    if (Test-Path "$srcDir\auto_update_helper.exe") {
        Copy-Item -Path "$srcDir\auto_update_helper.exe" -Destination "$DistDir\tools\auto_update_helper.exe" -Force
        Write-Host "  auto_update_helper.exe -> dist\tools\" -ForegroundColor Green
    }

    # --- Remote server ---
    if (Test-Path "$srcDir\remote_server.exe") {
        Copy-Item -Path "$srcDir\remote_server.exe" -Destination "$DistDir\remote_server.exe" -Force
        Write-Host "  remote_server.exe -> dist\" -ForegroundColor Green
    }

    # --- Explorer command injector ---
    if (Test-Path "$srcDir\explorer_command_injector.dll") {
        Copy-Item -Path "$srcDir\explorer_command_injector.dll" -Destination "$DistDir\appx\zed_explorer_command_injector.dll" -Force
        Write-Host "  explorer_command_injector.dll -> dist\appx\" -ForegroundColor Green
    }

    # --- External DLLs ---
    Write-Host ""
    Write-Host "  Downloading external dependencies..." -ForegroundColor White

    if (-not $SkipConpty) {
        Download-Conpty
    }
    else {
        Write-Host "  [SKIP] ConPTY skipped." -ForegroundColor Gray
    }

    if (-not $SkipAGS) {
        Download-AGS
    }
    else {
        Write-Host "  [SKIP] AMD AGS skipped." -ForegroundColor Gray
    }

    # --- PDBs (debug only) ---
    if (-not $Release) {
        Write-Host ""
        Write-Host "  Copying debug symbols..." -ForegroundColor White
        $pdbNames = @("rzed.pdb", "cli.pdb", "auto_update_helper.pdb",
            "explorer_command_injector.pdb", "remote_server.pdb")
        foreach ($pdbName in $pdbNames) {
            $pdbPath = "$srcDir\$pdbName"
            if (Test-Path $pdbPath) {
                Copy-Item -Path $pdbPath -Destination "$DistDir\$pdbName" -Force
                Write-Host "  $pdbName -> dist\" -ForegroundColor Gray
            }
        }
    }
}

# ============================================================================
# Step 5: Verify distribution
# ============================================================================

function Verify-Distribution {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "   Step 5: Verifying Distribution" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan

    $required = @("$DistDir\RZed.exe")
    $optional = @(
        "$DistDir\conpty.dll",
        "$DistDir\amd_ags_x64.dll",
        "$DistDir\bin\zed.exe",
        "$DistDir\tools\auto_update_helper.exe",
        "$DistDir\remote_server.exe"
    )

    $allOk = $true

    Write-Host ""
    Write-Host "  Required files:" -ForegroundColor White
    foreach ($file in $required) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $sizeMB = [math]::Round($size / 1048576, 1)
            Write-Host "  [OK] $file ($sizeMB MB)" -ForegroundColor Green
        }
        else {
            Write-Host "  [FAIL] $file is missing!" -ForegroundColor Red
            $allOk = $false
        }
    }

    Write-Host ""
    Write-Host "  Optional files:" -ForegroundColor White
    foreach ($file in $optional) {
        if (Test-Path $file) {
            $size = (Get-Item $file).Length
            $sizeKB = [math]::Round($size / 1024, 1)
            Write-Host "  [OK] $file ($sizeKB KB)" -ForegroundColor Green
        }
        else {
            Write-Host "  [--] $file not found (optional)" -ForegroundColor Gray
        }
    }

    # Check if binary can start
    Write-Host ""
    Write-Host "  Testing binary..." -ForegroundColor White
    $zedExe = "$DistDir\RZed.exe"
    try {
        $versionOutput = & $zedExe --version 2>&1
        Write-Host "  RZed.exe --version: $versionOutput" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not run RZed.exe --version" -ForegroundColor Yellow
        Write-Host "  $_" -ForegroundColor Yellow
    }

    if ($allOk) {
        $resolved = Resolve-Path $DistDir
        Write-Host ""
        Write-Host "  Distribution ready: $resolved" -ForegroundColor Cyan
    }
    else {
        Write-Host ""
        Write-Host "  [WARN] Some required files are missing!" -ForegroundColor Red
    }
}

# ============================================================================
# Main
# ============================================================================

function Main {
    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host "   Zed Editor - Build & Distribute Script" -ForegroundColor Magenta
    Write-Host "   Architecture: $Arch | Profile: $BuildProfile | Output: $DistDir" -ForegroundColor Magenta
    Write-Host "============================================================================" -ForegroundColor Magenta

    $startTime = Get-Date

    Set-Location $ProjectRoot

    # Show Zed version from Cargo.toml
    try {
        $metadata = cargo metadata --no-deps --offline 2>$null | ConvertFrom-Json
        if ($metadata) {
            $pkg = $metadata.packages | Where-Object { $_.name -eq "zed" } | Select-Object -First 1
            if ($pkg) {
                Write-Host "  Zed version: $($pkg.version)" -ForegroundColor Gray
            }
        }
    }
    catch {
        Write-Host "  Could not determine Zed version" -ForegroundColor Gray
    }

    Check-Dependencies
    Build-Binaries
    Assemble-Distribution
    Verify-Distribution

    $elapsed = (Get-Date) - $startTime
    $minutes = $elapsed.Minutes
    $seconds = $elapsed.Seconds
    $timeStr = "${minutes}min ${seconds}s"

    $resolved = Resolve-Path $DistDir

    Write-Host ""
    Write-Host "============================================================================" -ForegroundColor Magenta
    Write-Host "   DONE! Build time: $timeStr" -ForegroundColor Magenta
    Write-Host "   Distribution: $resolved" -ForegroundColor Magenta
    Write-Host "   Run: .\$DistDir\RZed.exe" -ForegroundColor Magenta
    Write-Host "============================================================================" -ForegroundColor Magenta
}

Main
