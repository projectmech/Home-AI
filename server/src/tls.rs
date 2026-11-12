//! Self-signed TLS certificate for the built-in HTTPS listener.
//!
//! The certificate is created once, at install time or first start, and kept
//! in `<data dir>/tls/`. It is not trusted by any browser until the user
//! verifies its fingerprint and installs it; nothing here claims otherwise.

use std::path::Path;

use sha2::{Digest, Sha256};

/// Kept under 825 days: Apple platforms reject longer-lived certificates even
/// when the user has installed them as trusted.
const VALID_DAYS: i64 = 820;

const CERT_FILE: &str = "cert.pem";
const KEY_FILE: &str = "key.pem";

pub struct TlsMaterial {
    pub cert_pem: String,
    pub key_pem: String,
    /// SHA-256 of the certificate, as browsers display it.
    pub fingerprint: String,
    /// True when this call created the certificate.
    pub created: bool,
}

/// SHA-256 fingerprint (`AA:BB:…`) of the first certificate in a PEM file.
pub fn fingerprint(cert_pem: &str) -> Result<String, String> {
    let mut reader = std::io::BufReader::new(cert_pem.as_bytes());
    let der = rustls_pemfile::certs(&mut reader)
        .next()
        .ok_or_else(|| "no certificate in PEM".to_string())?
        .map_err(|e| format!("bad certificate PEM: {e}"))?;
    let digest = Sha256::digest(der.as_ref());
    Ok(digest
        .iter()
        .map(|b| format!("{b:02X}"))
        .collect::<Vec<_>>()
        .join(":"))
}

fn generate(names: &[String]) -> Result<(String, String), String> {
    let mut params =
        rcgen::CertificateParams::new(names.to_vec()).map_err(|e| format!("names: {e}"))?;
    let mut dn = rcgen::DistinguishedName::new();
    dn.push(rcgen::DnType::CommonName, "Home AI (self-signed)");
    params.distinguished_name = dn;
    let now = time::OffsetDateTime::now_utc();
    params.not_before = now - time::Duration::days(1);
    params.not_after = now + time::Duration::days(VALID_DAYS);

    let key = rcgen::KeyPair::generate().map_err(|e| format!("key: {e}"))?;
    let cert = params
        .self_signed(&key)
        .map_err(|e| format!("certificate: {e}"))?;
    Ok((cert.pem(), key.serialize_pem()))
}

#[cfg(unix)]
fn write_private(path: &Path, contents: &str) -> std::io::Result<()> {
    use std::io::Write;
    use std::os::unix::fs::OpenOptionsExt;
    let mut f = std::fs::OpenOptions::new()
        .write(true)
        .create(true)
        .truncate(true)
        .mode(0o600)
        .open(path)?;
    f.write_all(contents.as_bytes())
}

#[cfg(not(unix))]
fn write_private(path: &Path, contents: &str) -> std::io::Result<()> {
    std::fs::write(path, contents)
}

/// Load the certificate from `dir`, creating it for `names` if absent.
/// An existing certificate is never replaced, so its fingerprint is stable.
pub fn load_or_create(dir: &Path, names: &[String]) -> Result<TlsMaterial, String> {
    let cert_path = dir.join(CERT_FILE);
    let key_path = dir.join(KEY_FILE);

    let created = !(cert_path.exists() && key_path.exists());
    if created {
        std::fs::create_dir_all(dir).map_err(|e| format!("{}: {e}", dir.display()))?;
        let (cert_pem, key_pem) = generate(names)?;
        write_private(&key_path, &key_pem).map_err(|e| format!("{}: {e}", key_path.display()))?;
        std::fs::write(&cert_path, &cert_pem)
            .map_err(|e| format!("{}: {e}", cert_path.display()))?;
    }

    let cert_pem =
        std::fs::read_to_string(&cert_path).map_err(|e| format!("{}: {e}", cert_path.display()))?;
    let key_pem =
        std::fs::read_to_string(&key_path).map_err(|e| format!("{}: {e}", key_path.display()))?;
    let fingerprint = fingerprint(&cert_pem)?;
    Ok(TlsMaterial {
        cert_pem,
        key_pem,
        fingerprint,
        created,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn certificate_is_created_once_and_fingerprint_is_stable() {
        let dir = tempfile::tempdir().unwrap();
        let names = vec!["localhost".to_string(), "192.168.1.100".to_string()];

        let first = load_or_create(dir.path(), &names).unwrap();
        assert!(first.created);
        assert!(first.cert_pem.contains("BEGIN CERTIFICATE"));
        assert!(first.key_pem.contains("PRIVATE KEY"));
        // 32 bytes as "AA:BB:…": 64 hex digits and 31 colons.
        assert_eq!(first.fingerprint.len(), 95);

        let second = load_or_create(dir.path(), &["other.example".to_string()]).unwrap();
        assert!(!second.created);
        assert_eq!(first.fingerprint, second.fingerprint);
    }

    #[cfg(unix)]
    #[test]
    fn private_key_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let dir = tempfile::tempdir().unwrap();
        load_or_create(dir.path(), &["localhost".to_string()]).unwrap();
        let mode = std::fs::metadata(dir.path().join(KEY_FILE))
            .unwrap()
            .permissions()
            .mode();
        assert_eq!(mode & 0o777, 0o600);
    }

    #[test]
    fn fingerprint_rejects_garbage() {
        assert!(fingerprint("not a certificate").is_err());
    }
}
