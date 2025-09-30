//! Public API exposed to Flutter through flutter_rust_bridge.

use flutter_rust_bridge::frb;
use messie_matrix as matrix;

/// Returns a "pong" string confirming that the Rust core is reachable from Flutter.
#[frb]
pub fn ping() -> String {
    matrix::ping().expect("ping should never fail")
}
