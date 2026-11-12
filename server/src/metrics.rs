//! Real host metrics via `sysinfo`. Values that cannot be measured are
//! reported as `null`, never estimated.

use std::sync::Mutex;

use serde::Serialize;
use sysinfo::{DiskKind, Disks, ProcessesToUpdate, System};

#[derive(Debug, Clone, Serialize)]
pub struct DiskInfo {
    pub name: String,
    pub mount: String,
    pub file_system: String,
    /// "ssd", "hdd" or "unknown" as reported by the OS.
    pub kind: &'static str,
    pub total_bytes: u64,
    pub available_bytes: u64,
}

#[derive(Debug, Clone, Serialize)]
pub struct MetricsSnapshot {
    pub ts: i64,
    pub uptime_s: u64,
    /// `null` until two samples exist; CPU usage is a delta between samples.
    pub cpu_usage_percent: Option<f32>,
    pub per_core_percent: Option<Vec<f32>>,
    /// Not available on Windows.
    pub load_average: Option<[f64; 3]>,
    pub mem_total_bytes: u64,
    pub mem_used_bytes: u64,
    pub mem_available_bytes: u64,
    pub swap_total_bytes: u64,
    pub swap_used_bytes: u64,
    pub process_rss_bytes: Option<u64>,
    pub disks: Vec<DiskInfo>,
    pub cpu_model: String,
    pub logical_cores: usize,
    pub physical_cores: Option<usize>,
    pub os_name: Option<String>,
    pub os_version: Option<String>,
    pub kernel_version: Option<String>,
    pub host_name: Option<String>,
    pub app_version: &'static str,
}

struct Inner {
    sys: System,
    cpu_samples: u32,
}

pub struct MetricsCollector {
    inner: Mutex<Inner>,
    last: Mutex<Option<MetricsSnapshot>>,
}

impl Default for MetricsCollector {
    fn default() -> Self {
        Self {
            inner: Mutex::new(Inner {
                sys: System::new(),
                cpu_samples: 0,
            }),
            last: Mutex::new(None),
        }
    }
}

pub fn disk_kind(kind: DiskKind) -> &'static str {
    match kind {
        DiskKind::SSD => "ssd",
        DiskKind::HDD => "hdd",
        DiskKind::Unknown(_) => "unknown",
    }
}

pub fn disks() -> Vec<DiskInfo> {
    Disks::new_with_refreshed_list()
        .iter()
        .map(|d| DiskInfo {
            name: d.name().to_string_lossy().into_owned(),
            mount: d.mount_point().to_string_lossy().into_owned(),
            file_system: d.file_system().to_string_lossy().into_owned(),
            kind: disk_kind(d.kind()),
            total_bytes: d.total_space(),
            available_bytes: d.available_space(),
        })
        .collect()
}

impl MetricsCollector {
    /// Take a fresh sample. Blocking; call from the blocking pool.
    pub fn collect(&self) -> MetricsSnapshot {
        let mut g = self.inner.lock().unwrap_or_else(|e| e.into_inner());
        g.sys.refresh_cpu_usage();
        g.sys.refresh_memory();
        g.cpu_samples = g.cpu_samples.saturating_add(1);
        let have_cpu = g.cpu_samples >= 2;

        let process_rss_bytes = sysinfo::get_current_pid().ok().and_then(|pid| {
            g.sys
                .refresh_processes(ProcessesToUpdate::Some(&[pid]), true);
            g.sys.process(pid).map(|p| p.memory())
        });

        let load_average = if cfg!(windows) {
            None
        } else {
            let l = System::load_average();
            Some([l.one, l.five, l.fifteen])
        };

        let cpus = g.sys.cpus();
        let snap = MetricsSnapshot {
            ts: crate::now(),
            uptime_s: System::uptime(),
            cpu_usage_percent: have_cpu.then(|| g.sys.global_cpu_usage()),
            per_core_percent: have_cpu.then(|| cpus.iter().map(|c| c.cpu_usage()).collect()),
            load_average,
            mem_total_bytes: g.sys.total_memory(),
            mem_used_bytes: g.sys.used_memory(),
            mem_available_bytes: g.sys.available_memory(),
            swap_total_bytes: g.sys.total_swap(),
            swap_used_bytes: g.sys.used_swap(),
            process_rss_bytes,
            disks: disks(),
            cpu_model: cpus
                .first()
                .map(|c| c.brand().trim().to_string())
                .unwrap_or_default(),
            logical_cores: cpus.len(),
            physical_cores: g.sys.physical_core_count(),
            os_name: System::name(),
            os_version: System::os_version(),
            kernel_version: System::kernel_version(),
            host_name: System::host_name(),
            app_version: env!("CARGO_PKG_VERSION"),
        };
        *self.last.lock().unwrap_or_else(|e| e.into_inner()) = Some(snap.clone());
        snap
    }

    pub fn last(&self) -> Option<MetricsSnapshot> {
        self.last.lock().unwrap_or_else(|e| e.into_inner()).clone()
    }
}
