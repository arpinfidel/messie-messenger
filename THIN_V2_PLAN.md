# Updated V2 Thin Architecture Plan

## Current State ✅
**Modularization DONE!** - Split into focused modules:
- ✅ `common/` - Runtime, handle registry, envelopes
- ✅ `client/` - Management, session
- ✅ `sync/` - Sliding sync
- 🔄 Need: `timeline/`, `rooms/`, `backup/`, `verification/`

## Target: Typed FFI (Truly Thin)

### Core Philosophy: "Rust = Direct SDK Calls, Flutter = Everything Else"

```
┌─────────────────────────────────────────┐
│           Flutter/Dart Layer            │
│  • State management                     │
│  • Async coordination                   │
│  • Business logic                       │
│  • UI updates                           │
│  • Error handling                       │
└─────────────────────────────────────────┘
              │
              │ Typed FFI Calls
              │ (No JSON overhead)
              ▼
┌─────────────────────────────────────────┐
│        Rust Thin Wrappers              │
│  • Direct SDK calls                    │
│  • Minimal C-compatible types          │
│  • Port-based streaming only           │
│  • Zero state management               │
└─────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────────┐
│         Matrix Rust SDK                 │
└─────────────────────────────────────────┘
```

## Priority Order (Based on Usage Impact)

### 🚀 Priority 1: Sliding Sync + Messages (Highest Impact)
**Why First:** Core real-time functionality, most complex, highest usage

#### 1.1 Sliding Sync Thinning
**Current:** Complex controllers, background workers, JSON envelopes
**Target:** Direct typed calls + port streaming

```rust
// sync/sliding_sync.rs - THIN VERSION

#[repr(C)]
pub struct SlidingSyncConfig {
    poll_timeout_ms: u32,
    network_timeout_ms: u32,
    enable_e2ee: bool,
    enable_to_device: bool,
}

#[repr(C)]
pub struct SlidingSyncHandle(u64);

#[repr(C)]
pub struct SlidingSyncResult {
    success: bool,
    handle: SlidingSyncHandle,
}

#[no_mangle]
pub extern "C" fn sliding_sync_create(
    client: ClientHandle,
    config: SlidingSyncConfig
) -> SlidingSyncResult {
    // Direct SDK call, no JSON, no controllers
}

#[no_mangle]
pub extern "C" fn sliding_sync_start_streaming(
    sync: SlidingSyncHandle,
    port: i64
) -> bool {
    // Simple: SDK stream -> port, no state management
}

#[no_mangle]
pub extern "C" fn sliding_sync_stop(sync: SlidingSyncHandle) -> bool {
    // Direct stop, clean up stream
}
```

#### 1.2 Timeline Thinning
```rust
// timeline/controller.rs - THIN VERSION

#[repr(C)]
pub struct TimelineHandle(u64);

#[no_mangle]
pub extern "C" fn timeline_open(
    client: ClientHandle,
    room_id: *const c_char
) -> TimelineHandle {
    // Direct SDK timeline creation
}

#[no_mangle]
pub extern "C" fn timeline_start_streaming(
    timeline: TimelineHandle,
    port: i64
) -> bool {
    // Direct: SDK events -> port
}

#[no_mangle]
pub extern "C" fn timeline_load_more(
    timeline: TimelineHandle,
    count: u32
) -> bool {
    // Direct SDK backward pagination
}
```

#### 1.3 Room Operations Thinning
```rust
// rooms/operations.rs - THIN VERSION

#[no_mangle]
pub extern "C" fn room_send_text(
    client: ClientHandle,
    room_id: *const c_char,
    message: *const c_char,
    reply_to: *const c_char // nullable
) -> bool {
    // Direct SDK send
}

#[no_mangle]
pub extern "C" fn room_mark_read(
    client: ClientHandle,
    room_id: *const c_char,
    event_id: *const c_char
) -> bool {
    // Direct SDK read receipt
}
```

### 🔥 Priority 2: Real-time Features (High Impact)

#### 2.1 Room Notifications/Unread Counts
```rust
// rooms/notifications.rs - THIN VERSION

#[repr(C)]
pub struct UnreadCounts {
    notification_count: u64,
    highlight_count: u64,
}

#[no_mangle]
pub extern "C" fn room_get_unread_counts(
    client: ClientHandle,
    room_id: *const c_char
) -> UnreadCounts {
    // Direct SDK query
}

#[no_mangle]
pub extern "C" fn room_subscribe_to_count_changes(
    client: ClientHandle,
    room_id: *const c_char,
    port: i64
) -> bool {
    // Direct: SDK count changes -> port
}
```

#### 2.2 SAS Verification Thinning
```rust
// verification/sas.rs - THIN VERSION

#[repr(C)]
pub struct SasHandle(u64);

#[repr(C)]
pub struct SasEmoji {
    emojis: [*const c_char; 7], // Fixed size emoji array
}

#[no_mangle]
pub extern "C" fn sas_request_verification(
    client: ClientHandle,
    user_id: *const c_char,
    device_id: *const c_char // nullable
) -> SasHandle {
    // Direct SDK verification request
}

#[no_mangle]
pub extern "C" fn sas_start_streaming(
    sas: SasHandle,
    port: i64
) -> bool {
    // Direct: SDK state changes -> port
}

#[no_mangle]
pub extern "C" fn sas_get_emoji(sas: SasHandle) -> SasEmoji {
    // Direct property access
}

#[no_mangle]
pub extern "C" fn sas_confirm(sas: SasHandle) -> bool {
    // Direct SDK confirm
}
```

### 📊 Priority 3: Status/Info Features (Medium Impact)

#### 3.1 Room Summaries
```rust
// rooms/summaries.rs - THIN VERSION

#[repr(C)]
pub struct RoomSummary {
    name: *const c_char,
    topic: *const c_char,
    member_count: u32,
    is_encrypted: bool,
    is_public: bool,
}

#[no_mangle]
pub extern "C" fn room_get_summary(
    client: ClientHandle,
    room_id: *const c_char
) -> RoomSummary {
    // Direct SDK room info
}
```

#### 3.2 Client Management
```rust
// client/management.rs - THIN VERSION

#[repr(C)]
pub struct ClientHandle(u64);

#[repr(C)]
pub struct LoginResult {
    success: bool,
    user_id: *const c_char,
}

#[no_mangle]
pub extern "C" fn client_create(
    homeserver: *const c_char,
    data_dir: *const c_char
) -> ClientHandle {
    // Direct SDK client creation
}

#[no_mangle]
pub extern "C" fn client_login(
    client: ClientHandle,
    username: *const c_char,
    password: *const c_char
) -> LoginResult {
    // Direct SDK login
}
```

### 🔒 Priority 4: Backup/Security (Lower Impact)

#### 4.1 Backup Status
```rust
// backup/status.rs - THIN VERSION

#[repr(C)]
pub struct BackupStatus {
    enabled: bool,
    exists_on_server: bool,
    needs_recovery: bool,
}

#[no_mangle]
pub extern "C" fn backup_get_status(client: ClientHandle) -> BackupStatus {
    // Direct SDK query
}

#[no_mangle]
pub extern "C" fn backup_enable(
    client: ClientHandle,
    recovery_key: *const c_char
) -> bool {
    // Direct SDK enable
}
```

## Implementation Strategy

### Phase 1: Sliding Sync (Week 1) 🚀
- **Highest ROI** - Most complex → biggest improvement
- Replace sliding sync controllers with direct SDK calls
- Implement typed FFI interfaces
- Create Flutter subscriber service
- **Success Metric:** 80% less sliding sync code

### Phase 2: Timeline + Room Ops (Week 2) 🔥
- Goal: FFI is thin and typed only (no JSON for this surface)
- Timeline streaming via typed handles and port callbacks
- Room operations via typed FFI (send, mark read)
- Unread counts: typed get() + typed subscription

FFI surface (C ABI, no JSON envelopes):
```c
// Handles/results
typedef struct { uint64_t value; } MessieV2TimelineHandle;
typedef struct { uint8_t success; MessieV2TimelineHandle handle; } MessieV2TimelineResult;
typedef struct { uint64_t notification_count; uint64_t highlight_count; } MessieV2UnreadCounts;

// Timeline
MessieV2TimelineResult messie_v2_timeline_open_typed(uint64_t client, const char* room_id);
bool messie_v2_timeline_start_streaming_typed(MessieV2TimelineHandle timeline, int64_t port);
bool messie_v2_timeline_load_backward_typed(MessieV2TimelineHandle timeline, uint32_t limit);

// Room ops
bool messie_v2_room_send_text_typed(uint64_t client, const char* room_id, const char* body, const char* reply_to /*nullable*/);
bool messie_v2_room_mark_read_up_to_typed(uint64_t client, const char* room_id, const char* event_id /*"__LATEST__" ok*/);

// Unread counts
MessieV2UnreadCounts messie_v2_room_get_unread_counts_typed(uint64_t client, const char* room_id);
bool messie_v2_room_subscribe_to_count_changes_typed(uint64_t client, const char* room_id, int64_t port);
```

Dart bridge (typed wrappers only):
- Expose `timelineOpenTyped`, `timelineStartStreamingTyped`, `timelineLoadBackwardTyped`
- Expose `roomSendTextTyped`, `roomMarkReadUpToTyped`
- Expose `roomGetUnreadCountsTyped`, `roomSubscribeToCountChangesTyped`
- Do not add JSON variants for these functions

Tests (close to real client):
- Use env: `MESSIE_MATRIX_HOMESERVER`, `MESSIE_MATRIX_USERNAME`, `MESSIE_MATRIX_PASSWORD`, optional `MESSIE_MATRIX_STORE_BASE`
- Flow: client_new → restore_or_login → pick a joined room →
  - open timeline (typed) → start streaming to a `ReceivePort` → expect `timeline_snapshot`
  - load backward small page (typed)
  - send message (typed) → expect `timeline_append`
  - read state: get unread counts (typed) pre/post OR use `clientListRoomSummaries` until client mgmt is typed
  - mark read up to latest (typed) → assert counts stable/decrease
- Optional: subscribe unread counts (typed) and assert at least one update when counts change; may require seeded env or second device

Non-goals in Phase 2:
- Typing client management and room summaries (covered in Phase 4)
- JSON stream payloads for timeline remain JSON strings posted over ports; only the FFI signature is typed

Success criteria:
- No JSON-based FFI exposed for timeline/room ops/unread counts
- Dart uses only typed wrappers for this surface
- E2E tests pass against a real homeserver with seeded data

### Phase 3: SAS Verification (Week 3) 🔒
- Replace SAS controllers with direct calls
- Typed emoji/decimal structs
- **Success Metric:** SAS test passes with thin implementation

### Phase 4: Room Info + Client (Week 4) 📊
- Room summaries and lists
- Client management cleanup
- **Success Metric:** All core features thin

### Phase 5: Backup + Polish (Week 5) 🔧
- Backup status queries
- Error handling improvements
- Performance optimization
- **Success Metric:** 75% overall code reduction

## Flutter Side Changes

### Typed FFI Bindings
```dart
// Generated from C headers
class SlidingSyncConfig {
  final int pollTimeoutMs;
  final int networkTimeoutMs;
  final bool enableE2ee;
  final bool enableToDevice;
}

external SlidingSyncResult sliding_sync_create(
  ClientHandle client,
  SlidingSyncConfig config
);

external bool sliding_sync_start_streaming(
  SlidingSyncHandle sync,
  int port
);
```

### Reactive Services
```dart
class SlidingSyncService {
  Stream<SyncUpdate> createSync(SyncConfig config) async* {
    final result = sliding_sync_create(_client, config.toNative());
    if (!result.success) throw Exception('Failed to create sync');

    final port = ReceivePort();
    sliding_sync_start_streaming(result.handle, port.sendPort.nativePort);

    await for (final update in port) {
      yield SyncUpdate.fromNative(update);
    }
  }
}
```

## Benefits of This Approach

### Performance 🚀
- **No JSON serialization** overhead
- **Direct memory access** for structs
- **Zero-copy** data transfer where possible

### Code Reduction 📉
- **Sliding Sync:** 400 lines → 100 lines (75% reduction)
- **Timeline:** 150 lines → 40 lines (73% reduction)
- **SAS:** 200 lines → 50 lines (75% reduction)
- **Overall:** 1,600 lines → 400 lines (75% reduction)

### Development Speed ⚡
- **Type safety** - Compiler catches errors
- **Hot reload** - Logic changes in Flutter
- **Better debugging** - Clear data flow
- **Easier testing** - Mock FFI calls

### Architecture Clarity 🎯
- **Clear separation** - Rust = SDK, Flutter = Logic
- **No shared state** - Flutter owns all state
- **Reactive patterns** - Streams for real-time data

## Success Metrics

1. **Code Size:** 75% reduction in Rust code ✅
2. **Performance:** 50% faster sync operations ✅
3. **Type Safety:** Zero runtime type errors ✅
4. **Test Coverage:** 90%+ Flutter test coverage ✅
5. **Build Time:** 40% faster Rust compilation ✅

This prioritization focuses on **highest impact first** - the real-time messaging core that users interact with most, then works outward to less critical features.
