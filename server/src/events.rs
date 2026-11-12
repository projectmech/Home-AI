//! In-process event bus. Bounded: a slow WebSocket client lags and is
//! resynchronised with a full snapshot instead of growing a queue.

use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;

use serde::Serialize;
use tokio::sync::broadcast;

use crate::devices::Device;
use crate::metrics::MetricsSnapshot;

#[derive(Debug, Clone, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Event {
    DeviceState { device: Device },
    Metrics { metrics: MetricsSnapshot },
}

#[derive(Debug, Clone, Serialize)]
pub struct Envelope {
    pub seq: u64,
    pub ts: i64,
    #[serde(flatten)]
    pub event: Event,
}

pub struct EventBus {
    tx: broadcast::Sender<Arc<Envelope>>,
    seq: AtomicU64,
}

impl Default for EventBus {
    fn default() -> Self {
        let (tx, _) = broadcast::channel(256);
        Self {
            tx,
            seq: AtomicU64::new(0),
        }
    }
}

impl EventBus {
    pub fn publish(&self, event: Event) {
        let env = Envelope {
            seq: self.seq.fetch_add(1, Ordering::SeqCst) + 1,
            ts: crate::now(),
            event,
        };
        // No subscribers is not an error.
        let _ = self.tx.send(Arc::new(env));
    }

    pub fn subscribe(&self) -> broadcast::Receiver<Arc<Envelope>> {
        self.tx.subscribe()
    }

    pub fn subscriber_count(&self) -> usize {
        self.tx.receiver_count()
    }

    pub fn current_seq(&self) -> u64 {
        self.seq.load(Ordering::SeqCst)
    }
}
