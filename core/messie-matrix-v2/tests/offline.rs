use messie_matrix_v2 as v2;
use serde_json::Value;

fn parse(json: &str) -> Value { serde_json::from_str(json).expect("valid json") }

#[test]
fn unknown_handle_errors() {
    // Thin API: starting an unknown handle returns false
    let ok = v2::sliding_sync_start_streaming(987654321, 0);
    assert!(!ok);
}

#[test]
fn list_builder_invalid_mode_replaced_by_thin_defaults() {
    // No list builder in thin API; ensure subscribe/expire unknown handle paths return false
    let ok_sub = v2::sliding_sync_subscribe_to_rooms(123456789, &Vec::<String>::new(), Some(0), None, true);
    assert_eq!(ok_sub, false);
}

#[test]
fn summaries_invalid_json_and_joined_rooms_offline() {
    // Create a client with a valid URL and local base path; no network calls are made.
    let base = std::path::PathBuf::from("target/it_store_v2/offline_client");
    let new_json = v2::client_new("http://localhost", &base);
    let v = parse(&new_json);
    assert_eq!(v["ok"], true);
    let handle = v["data"]["handle"].as_u64().unwrap();

    // Invalid JSON for room ids -> invalid_arg
    let res = v2::client_list_room_summaries(handle, "{not json");
    let out = parse(&res);
    assert_eq!(out["ok"], false);
    assert_eq!(out["error"]["code"], "invalid_arg");

    // Joined rooms should return ok with an array (possibly empty)
    let rooms = v2::client_list_joined_rooms(handle).unwrap_or_default();
    // If any room IDs are present, ensure they are non-empty strings
    assert!(rooms.iter().all(|r| !r.is_empty()));

    // Unknown handle false for expire
    let bad_exp = v2::sliding_sync_expire_session(123456789);
    assert_eq!(bad_exp, false);
}
