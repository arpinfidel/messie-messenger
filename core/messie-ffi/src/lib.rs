//! Handwritten FFI bindings for Messie until flutter_rust_bridge codegen is
//! fully wired in. The functions in `api.rs` expose a thin JSON interface
//! consumed from Dart via `dart:ffi`.

mod api;
mod bridge_generated;

pub use api::*;
pub use bridge_generated::*;
