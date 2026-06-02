#![allow(clippy::disallowed_methods, reason = "build scripts are exempt")]
use std::process::Command;

/// Prebuilt `webrtc.lib` references MSVC STL symbols (`__std_search_1`, etc.).
#[cfg(all(target_os = "windows", target_env = "msvc"))]
fn link_webrtc_msvc_stl() {
    use cc::windows_registry;
    use std::path::PathBuf;

    let Ok(target) = std::env::var("TARGET") else {
        return;
    };
    let Ok(arch) = std::env::var("CARGO_CFG_TARGET_ARCH") else {
        return;
    };
    let arch_dir = match arch.as_str() {
        "x86_64" => "x64",
        "aarch64" => "arm64",
        _ => return,
    };

    let lib_dir = find_newest_msvc_lib_dir(arch_dir).or_else(|| {
        let tool = windows_registry::find_tool(&target, "cl.exe")?;
        let spectre_lib = tool
            .path()
            .join(format!(r"..\..\..\..\lib\spectre\{arch_dir}"));
        let default_lib = tool.path().join(format!(r"..\..\..\..\lib\{arch_dir}"));
        if spectre_lib.exists() {
            Some(spectre_lib)
        } else if default_lib.exists() {
            Some(default_lib)
        } else {
            None
        }
    });

    let Some(lib_dir) = lib_dir else {
        println!("cargo:warning=MSVC lib directory not found for WebRTC linking");
        return;
    };

    println!(
        "cargo:rustc-link-search=native={}",
        lib_dir.into_os_string().into_string().unwrap()
    );
    // Prebuilt WebRTC uses release (/MT) STL regardless of Zed profile.
    println!("cargo:rustc-link-lib=static=libcpmt");
}

#[cfg(all(target_os = "windows", target_env = "msvc"))]
fn find_newest_msvc_lib_dir(arch_dir: &str) -> Option<std::path::PathBuf> {
    use std::path::PathBuf;

    const MSVC_ROOTS: &[&str] = &[
        r"C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Tools\MSVC",
        r"C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Tools\MSVC",
        r"C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Tools\MSVC",
        r"C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
        r"C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC",
    ];

    let mut best: Option<(String, PathBuf)> = None;

    for root in MSVC_ROOTS {
        let Ok(entries) = std::fs::read_dir(root) else {
            continue;
        };
        for entry in entries.flatten() {
            let version = entry.file_name().to_string_lossy().into_owned();
            let spectre = entry
                .path()
                .join("lib")
                .join("spectre")
                .join(arch_dir);
            let normal = entry.path().join("lib").join(arch_dir);
            let lib_dir = if spectre.exists() { spectre } else { normal };
            if !lib_dir.exists() {
                continue;
            }
            if best
                .as_ref()
                .is_none_or(|(current, _)| version > *current)
            {
                best = Some((version, lib_dir));
            }
        }
    }

    best.map(|(_, path)| path)
}

fn main() {
    #[cfg(target_os = "linux")]
    {
        // Add rpaths for libraries that webrtc-sys dlopens at runtime.
        // This is mostly required for hosts with non-standard SO installation
        // locations such as NixOS.
        let dlopened_libs = ["libva", "libva-drm", "egl"];

        let mut rpath_dirs = std::collections::BTreeSet::new();
        for lib in &dlopened_libs {
            if let Some(libdir) = pkg_config::get_variable(lib, "libdir").ok() {
                rpath_dirs.insert(libdir);
            } else {
                eprintln!("zed build.rs: {lib} not found in pkg-config's path");
            }
        }

        for dir in &rpath_dirs {
            println!("cargo:rustc-link-arg=-Wl,-rpath,{dir}");
        }
    }

    if cfg!(target_os = "macos") {
        println!("cargo:rustc-env=MACOSX_DEPLOYMENT_TARGET=10.15.7");

        // Weakly link ReplayKit to ensure Zed can be used on macOS 10.15+.
        println!("cargo:rustc-link-arg=-Wl,-weak_framework,ReplayKit");

        // Seems to be required to enable Swift concurrency
        println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");

        // Register exported Objective-C selectors, protocols, etc
        println!("cargo:rustc-link-arg=-Wl,-ObjC");

        // weak link to support Catalina
        println!("cargo:rustc-link-arg=-Wl,-weak_framework,ScreenCaptureKit");
    }

    // Populate git sha environment variable if git is available
    println!("cargo:rerun-if-changed=../../.git/logs/HEAD");
    println!(
        "cargo:rustc-env=TARGET={}",
        std::env::var("TARGET").unwrap()
    );

    let git_sha = match std::env::var("ZED_COMMIT_SHA").ok() {
        Some(git_sha) => {
            // In deterministic build environments such as Nix, we inject the commit sha into the build script.
            Some(git_sha)
        }
        None => {
            if let Some(output) = Command::new("git")
                .args(["rev-parse", "HEAD"])
                .output()
                .ok()
                && output.status.success()
            {
                let git_sha = String::from_utf8_lossy(&output.stdout);
                Some(git_sha.trim().to_string())
            } else {
                None
            }
        }
    };

    if let Some(git_sha) = git_sha {
        println!("cargo:rustc-env=ZED_COMMIT_SHA={git_sha}");

        if let Some(build_identifier) = option_env!("GITHUB_RUN_NUMBER") {
            println!("cargo:rustc-env=ZED_BUILD_ID={build_identifier}");
        }

        if let Ok(build_profile) = std::env::var("PROFILE")
            && build_profile == "release"
        {
            // This is currently the best way to make `cargo build ...`'s build script
            // to print something to stdout without extra verbosity.
            println!("cargo::warning=Info: using '{git_sha}' hash for ZED_COMMIT_SHA env var");
        }
    }

    if cfg!(windows) {
        if cfg!(target_env = "msvc") {
            link_webrtc_msvc_stl();

            // todo(windows): This is to avoid stack overflow. Remove it when solved.
            println!("cargo:rustc-link-arg=/stack:{}", 8 * 1024 * 1024);
        }

        if cfg!(target_arch = "x86_64") || cfg!(target_arch = "aarch64") {
            let out_dir = std::env::var("OUT_DIR").unwrap();
            let out_dir: &std::path::Path = out_dir.as_ref();
            let target_dir = std::path::Path::new(&out_dir)
                .parent()
                .and_then(|p| p.parent())
                .and_then(|p| p.parent())
                .expect("Failed to find target directory");

            let conpty_dll_target = target_dir.join("conpty.dll");
            let open_console_target = target_dir.join("OpenConsole.exe");

            let conpty_url = "https://github.com/microsoft/terminal/releases/download/v1.24.10621.0/Microsoft.Windows.Console.ConPTY.1.24.260303001.nupkg";
            let nupkg_path = out_dir.join("conpty.nupkg.zip");
            let extract_dir = out_dir.join("conpty");

            let download_script = format!(
                "$ProgressPreference = 'SilentlyContinue'; [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '{}' -OutFile '{}'",
                conpty_url,
                nupkg_path.display()
            );

            let download_result = Command::new("powershell")
                .args([
                    "-NoProfile",
                    "-NonInteractive",
                    "-Command",
                    &download_script,
                ])
                .output();

            match download_result {
                Ok(output) if output.status.success() => {
                    println!("Downloaded conpty nupkg successfully");

                    let extract_script = format!(
                        "$ProgressPreference = 'SilentlyContinue'; Expand-Archive -Path '{}' -DestinationPath '{}' -Force",
                        nupkg_path.display(),
                        extract_dir.display()
                    );

                    let extract_result = Command::new("powershell")
                        .args(["-NoProfile", "-NonInteractive", "-Command", &extract_script])
                        .output();

                    match extract_result {
                        Ok(output) if output.status.success() => {
                            let (conpty_dll_source, open_console_source) =
                                if cfg!(target_arch = "x86_64") {
                                    (
                                        extract_dir.join("runtimes/win-x64/native/conpty.dll"),
                                        extract_dir
                                            .join("build/native/runtimes/x64/OpenConsole.exe"),
                                    )
                                } else {
                                    (
                                        extract_dir.join("runtimes/win-arm64/native/conpty.dll"),
                                        extract_dir
                                            .join("build/native/runtimes/arm64/OpenConsole.exe"),
                                    )
                                };

                            match std::fs::copy(&conpty_dll_source, &conpty_dll_target) {
                                Ok(_) => {
                                    println!("Copied conpty.dll to {}", conpty_dll_target.display())
                                }
                                Err(e) => println!(
                                    "cargo::warning=Failed to copy conpty.dll from {}: {}",
                                    conpty_dll_source.display(),
                                    e
                                ),
                            }

                            match std::fs::copy(&open_console_source, &open_console_target) {
                                Ok(_) => println!(
                                    "Copied OpenConsole.exe to {}",
                                    open_console_target.display()
                                ),
                                Err(e) => println!(
                                    "cargo::warning=Failed to copy OpenConsole.exe from {}: {}",
                                    open_console_source.display(),
                                    e
                                ),
                            }
                        }
                        Ok(output) => {
                            println!(
                                "cargo::warning=Failed to extract conpty nupkg: {}",
                                String::from_utf8_lossy(&output.stderr)
                            );
                        }
                        Err(e) => {
                            println!(
                                "cargo::warning=Failed to run PowerShell for extraction: {}",
                                e
                            );
                        }
                    }
                }
                Ok(output) => {
                    println!(
                        "cargo::warning=Failed to download conpty nupkg: {}",
                        String::from_utf8_lossy(&output.stderr)
                    );
                }
                Err(e) => {
                    println!(
                        "cargo::warning=Failed to run PowerShell for download: {}",
                        e
                    );
                }
            }
        }

        println!("cargo:rerun-if-env-changed=RELEASE_CHANNEL");
        println!("cargo:rerun-if-env-changed=GITHUB_RUN_NUMBER");

        #[cfg(windows)]
        {
            windows_resources::compile(false).expect("failed to compile Windows resources");
        }
    }

    #[cfg(any(target_os = "linux", target_os = "freebsd"))]
    prepare_app_icon_x11();
}

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
fn icon_path() -> std::path::PathBuf {
    use std::str::FromStr;

    let release_channel = option_env!("RELEASE_CHANNEL").unwrap_or("dev");
    let channel = match release_channel {
        "stable" => "",
        "preview" => "-preview",
        "nightly" => "-nightly",
        "dev" => "-dev",
        _ => "-dev",
    };

    #[cfg(windows)]
    let icon = format!("resources/windows/app-icon{}.ico", channel);
    #[cfg(not(windows))]
    let icon = format!("resources/app-icon{}.png", channel);

    std::path::PathBuf::from_str(&icon).unwrap()
}

#[cfg(any(target_os = "linux", target_os = "freebsd"))]
fn prepare_app_icon_x11() {
    use image::{ImageReader, imageops};
    use std::env;
    use std::path::Path;

    let out_dir = env::var("OUT_DIR").unwrap();

    let resized_image = ImageReader::open(icon_path())
        .unwrap()
        .decode()
        .unwrap()
        .resize(256, 256, imageops::FilterType::Lanczos3);

    // name should match include_bytes! call in src/zed.rs
    let icon_out_path = Path::new(&out_dir).join("app_icon.png");
    resized_image.save(&icon_out_path).expect("saving app icon");

    println!("cargo:rerun-if-env-changed=RELEASE_CHANNEL");
    println!("cargo:rerun-if-changed={}", icon_path().to_string_lossy());
}
