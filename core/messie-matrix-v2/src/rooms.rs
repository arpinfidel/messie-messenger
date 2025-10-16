use crate::client::CLIENTS;
use crate::common::handle_registry::Handle;
use crate::common::runtime::runtime;

#[derive(Debug, Clone)]
pub struct RoomSummary {
    pub room_id: String,
    pub name: String,
    pub avatar_url: Option<String>,
    pub notification_count: u64,
    pub highlight_count: u64,
    pub is_marked_unread: bool,
}

/// Build a typed room summary for the given room id.
pub fn room_get_summary(handle: Handle, room_id: &str) -> Option<RoomSummary> {
    let entry = { let reg = CLIENTS.read().ok()?; reg.get(handle).cloned()? };
    let runtime = runtime();
    let _guard = runtime.enter();
    let client = entry.client.clone();
    let rid = room_id.to_string();
    let fut = async move { super::build_room_summary_for_id(&client, &rid).await };
    let dto = runtime.block_on(fut)?;
    Some(RoomSummary {
        room_id: dto.room_id,
        name: dto.name,
        avatar_url: dto.avatar_url,
        notification_count: dto.notification_count,
        highlight_count: dto.highlight_count,
        is_marked_unread: dto.is_marked_unread,
    })
}
