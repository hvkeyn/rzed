fn main() {
    #[cfg(all(target_os = "windows", target_env = "msvc"))]
    add_spectre_link_search();
}

/// Adds spectre-mitigated CRT lib search path when installed; warns otherwise.
/// Upstream `msvc_spectre_libs` with the `error` feature aborts the build without
/// `Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre`.
#[cfg(all(target_os = "windows", target_env = "msvc"))]
fn add_spectre_link_search() {
    use cc::windows_registry;
    use std::env;

    let target = env::var("TARGET").expect("missing TARGET");
    let arch = env::var("CARGO_CFG_TARGET_ARCH").expect("missing CARGO_CFG_TARGET_ARCH");
    let arch = match arch.as_str() {
        "x86_64" => "x64",
        "x86" => "x86",
        "aarch64" | "arm64ec" => "arm64",
        "arm" => "arm32",
        _ => return,
    };

    let Some(tool) = windows_registry::find_tool(&target, "cl.exe") else {
        println!(
            "cargo:warning=cl.exe not found; spectre-mitigated libs were not linked"
        );
        return;
    };

    let spectre_libs = tool.path().join(format!(r"..\..\..\..\lib\spectre\{arch}"));

    if spectre_libs.exists() {
        println!(
            "cargo:rustc-link-search=native={}",
            spectre_libs.into_os_string().into_string().unwrap()
        );
    } else {
        println!(
            "cargo:warning=No spectre-mitigated libs were found. Install \
             Microsoft.VisualStudio.Component.VC.Runtimes.x86.x64.Spectre \
             via Visual Studio Installer for production builds."
        );
    }
}
