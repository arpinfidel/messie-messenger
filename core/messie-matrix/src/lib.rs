//! Messie Matrix SDK wrapper.

use anyhow::Result;

/// Simple ping function used for integration tests.
pub fn ping() -> Result<String> {
    Ok("pong".to_owned())
}
