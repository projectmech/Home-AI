//! Read-only hardware diagnostics. Describes the machine it runs on; anything
//! it cannot determine is reported as unknown.

use serde::Serialize;
use sysinfo::{Networks, System};

use crate::metrics::{self, DiskInfo};

/// Instruction sets this binary's release profile is allowed to require.
pub const BINARY_BASELINE: &str = "x86-64 baseline (SSE2); no AVX/AVX2 required";

#[derive(Debug, Clone, Serialize, PartialEq)]
pub struct CpuInfo {
    pub model: Option<String>,
    pub logical_cores: Option<usize>,
    pub physical_cores: Option<usize>,
    /// Instruction-set flags that could be detected (not exhaustive off Linux).
    pub flags: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct BlockDevice {
    pub name: String,
    pub model: Option<String>,
    pub size_bytes: Option<u64>,
    /// Some(true) = spinning disk, Some(false) = SSD, None = unknown.
    pub rotational: Option<bool>,
}

#[derive(Debug, Clone, Serialize)]
pub struct NetInterface {
    pub name: String,
    pub mac: String,
    pub addresses: Vec<String>,
}

#[derive(Debug, Clone, Serialize)]
pub struct HardwareReport {
    pub generated_at: i64,
    pub note: &'static str,
    pub os_name: Option<String>,
    pub os_version: Option<String>,
    pub kernel_version: Option<String>,
    pub arch: &'static str,
    /// "uefi", "bios" or "unknown".
    pub boot_mode: &'static str,
    pub cpu: CpuInfo,
    pub mem_total_bytes: u64,
    pub swap_total_bytes: u64,
    pub block_devices: Vec<BlockDevice>,
    pub filesystems: Vec<DiskInfo>,
    pub network: Vec<NetInterface>,
    pub smart: &'static str,
    pub binary_baseline: &'static str,
    pub warnings: Vec<String>,
}

/// Parse Linux `/proc/cpuinfo`.
pub fn parse_cpuinfo(text: &str) -> CpuInfo {
    let mut model = None;
    let mut logical = 0usize;
    let mut physical = None;
    let mut flags = Vec::new();
    for line in text.lines() {
        let Some((key, value)) = line.split_once(':') else {
            continue;
        };
        let (key, value) = (key.trim(), value.trim());
        match key {
            "processor" => logical += 1,
            "model name" if model.is_none() => model = Some(value.to_string()),
            "cpu cores" if physical.is_none() => physical = value.parse().ok(),
            "flags" if flags.is_empty() => {
                flags = value.split_whitespace().map(str::to_string).collect()
            }
            _ => {}
        }
    }
    CpuInfo {
        model,
        logical_cores: (logical > 0).then_some(logical),
        physical_cores: physical,
        flags,
    }
}

/// Compatibility warnings for a CPU against this binary's baseline.
pub fn cpu_warnings(cpu: &CpuInfo) -> Vec<String> {
    let mut w = Vec::new();
    if cpu.flags.is_empty() {
        w.push("CPU flags could not be read; instruction-set compatibility is unverified.".into());
        return w;
    }
    let has = |f: &str| cpu.flags.iter().any(|x| x == f);
    if !has("sse2") {
        w.push("CPU lacks SSE2: this binary cannot run here.".into());
    }
    if !has("lm") && cfg!(target_os = "linux") {
        w.push("CPU does not report 64-bit long mode.".into());
    }
    if !has("avx") {
        w.push(
            "CPU has no AVX. That is expected on a Core 2 Duo; builds must keep the x86-64 \
             baseline target and never use target-cpu=native."
                .into(),
        );
    }
    w
}

#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]
fn detected_flags() -> Vec<String> {
    let mut f = Vec::new();
    macro_rules! probe {
        ($($name:tt => $flag:expr),*) => {
            $( if std::arch::is_x86_feature_detected!($name) { f.push($flag.to_string()); } )*
        };
    }
    probe!("sse2" => "sse2", "sse3" => "pni", "ssse3" => "ssse3", "sse4.1" => "sse4_1",
           "sse4.2" => "sse4_2", "avx" => "avx", "avx2" => "avx2");
    f
}

#[cfg(not(any(target_arch = "x86", target_arch = "x86_64")))]
fn detected_flags() -> Vec<String> {
    Vec::new()
}

fn read_trim(path: &str) -> Option<String> {
    std::fs::read_to_string(path)
        .ok()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
}

/// Linux `/sys/block` scan. Empty on other systems.
fn block_devices() -> Vec<BlockDevice> {
    let Ok(dir) = std::fs::read_dir("/sys/block") else {
        return Vec::new();
    };
    let mut out = Vec::new();
    for entry in dir.flatten() {
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with("loop") || name.starts_with("ram") || name.starts_with("dm-") {
            continue;
        }
        let base = format!("/sys/block/{name}");
        out.push(BlockDevice {
            model: read_trim(&format!("{base}/device/model")),
            size_bytes: read_trim(&format!("{base}/size"))
                .and_then(|s| s.parse::<u64>().ok())
                .map(|sectors| sectors * 512),
            rotational: read_trim(&format!("{base}/queue/rotational")).and_then(|s| {
                match s.as_str() {
                    "1" => Some(true),
                    "0" => Some(false),
                    _ => None,
                }
            }),
            name,
        });
    }
    out.sort_by(|a, b| a.name.cmp(&b.name));
    out
}

pub fn collect() -> HardwareReport {
    let mut sys = System::new();
    sys.refresh_memory();
    sys.refresh_cpu_usage();

    let cpu = match std::fs::read_to_string("/proc/cpuinfo") {
        Ok(text) => parse_cpuinfo(&text),
        Err(_) => CpuInfo {
            model: sys.cpus().first().map(|c| c.brand().trim().to_string()),
            logical_cores: Some(sys.cpus().len()).filter(|n| *n > 0),
            physical_cores: sys.physical_core_count(),
            flags: detected_flags(),
        },
    };

    let boot_mode = if cfg!(target_os = "linux") {
        if std::path::Path::new("/sys/firmware/efi").exists() {
            "uefi"
        } else {
            "bios"
        }
    } else {
        "unknown"
    };

    let network = Networks::new_with_refreshed_list()
        .iter()
        .map(|(name, data)| NetInterface {
            name: name.clone(),
            mac: data.mac_address().to_string(),
            addresses: data.ip_networks().iter().map(|n| n.to_string()).collect(),
        })
        .collect();

    let warnings = cpu_warnings(&cpu);
    HardwareReport {
        generated_at: crate::now(),
        note: "Describes the machine this command ran on, which may not be the deployment target.",
        os_name: System::name(),
        os_version: System::os_version(),
        kernel_version: System::kernel_version(),
        arch: std::env::consts::ARCH,
        boot_mode,
        cpu,
        mem_total_bytes: sys.total_memory(),
        swap_total_bytes: sys.total_swap(),
        block_devices: block_devices(),
        filesystems: metrics::disks(),
        network,
        smart: "not collected (needs smartmontools and elevated access; planned for M5)",
        binary_baseline: BINARY_BASELINE,
        warnings,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// MOCK fixture shaped like a Core 2 Duo P8600 on Linux. Not captured from
    /// the user's Mac mini.
    const MOCK_CORE2: &str = "\
processor\t: 0
model name\t: Intel(R) Core(TM)2 Duo CPU     P8600  @ 2.40GHz
cpu cores\t: 2
flags\t\t: fpu vme de pse tsc msr pae mce cx8 apic sep mtrr pge mca cmov pat pse36 clflush dts acpi mmx fxsr sse sse2 ht tm pbe syscall nx lm constant_tsc pni dtes64 monitor ds_cpl vmx smx est tm2 ssse3 cx16 xtpr pdcm sse4_1 xsave lahf_lm

processor\t: 1
model name\t: Intel(R) Core(TM)2 Duo CPU     P8600  @ 2.40GHz
cpu cores\t: 2
flags\t\t: fpu sse sse2 lm
";

    #[test]
    fn parses_cpuinfo() {
        let cpu = parse_cpuinfo(MOCK_CORE2);
        assert_eq!(cpu.logical_cores, Some(2));
        assert_eq!(cpu.physical_cores, Some(2));
        assert!(cpu.model.as_deref().unwrap().contains("P8600"));
        assert!(cpu.flags.iter().any(|f| f == "sse4_1"));
        assert!(!cpu.flags.iter().any(|f| f == "avx"));
    }

    #[test]
    fn core2_gets_avx_warning_but_no_sse2_error() {
        let w = cpu_warnings(&parse_cpuinfo(MOCK_CORE2));
        assert!(w.iter().any(|m| m.contains("no AVX")));
        assert!(!w.iter().any(|m| m.contains("lacks SSE2")));
    }

    #[test]
    fn unknown_flags_are_reported_as_unverified() {
        let w = cpu_warnings(&parse_cpuinfo(""));
        assert_eq!(w.len(), 1);
        assert!(w[0].contains("unverified"));
    }

    #[test]
    fn live_report_serializes() {
        let r = collect();
        assert!(serde_json::to_string(&r)
            .unwrap()
            .contains("binary_baseline"));
    }
}
