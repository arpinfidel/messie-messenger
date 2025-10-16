pub mod runtime;
pub mod envelope;
pub mod handle_registry;

pub fn post_to_port(port: i64, payload: String) -> bool {
    allo_isolate::Isolate::new(port).post(payload)
}
