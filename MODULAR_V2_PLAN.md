# V2 Modular Restructuring Plan

## Current Problems
- 1,539 lines in single lib.rs file
- 38 static globals/structs mixed together
- 45+ public functions with no organization
- 7 feature areas intermingled

## Proposed Module Structure

```
messie-matrix-v2/src/
├── lib.rs                  # Re-exports and runtime setup
├── common/
│   ├── mod.rs
│   ├── handle_registry.rs  # Generic handle management
│   ├── envelope.rs         # JSON envelope helpers
│   └── runtime.rs          # Tokio runtime setup
├── client/
│   ├── mod.rs
│   ├── management.rs       # client_new, login, logout
│   └── session.rs          # Session persistence
├── sync/
│   ├── mod.rs
│   ├── sliding_sync.rs     # Sliding sync implementation
│   └── builder.rs          # Builder pattern helpers
├── timeline/
│   ├── mod.rs
│   └── controller.rs       # Timeline streaming
├── rooms/
│   ├── mod.rs
│   ├── operations.rs       # send, mark_read, etc.
│   ├── summaries.rs        # Room info, lists
│   └── notifications.rs    # Unread counts, subscriptions
├── backup/
│   ├── mod.rs
│   ├── status.rs          # Backup status
│   └── ssss.rs            # SSSS operations
├── verification/
│   ├── mod.rs
│   └── sas.rs             # SAS verification
└── test_helpers/
    ├── mod.rs
    └── functions.rs        # Test-only functions
```

## Module Responsibilities

### `common/` - Shared Infrastructure
- Handle registry (generic)
- JSON envelope helpers
- Runtime management
- Error handling

### `client/` - Client Lifecycle
- Client creation and authentication
- Session persistence
- Basic client operations

### `sync/` - Real-time Sync
- Sliding sync implementation
- Background streaming
- List management

### `timeline/` - Message Timeline
- Timeline streaming
- Message loading
- Event handling

### `rooms/` - Room Operations
- Room CRUD operations
- Message sending
- Read receipts
- Room summaries
- Notification subscriptions

### `backup/` - Backup & Recovery
- Backup status monitoring
- SSSS operations
- Key management

### `verification/` - Device Verification
- SAS verification flow
- Device trust management

### `test_helpers/` - Testing Support
- Test-only functions
- Mock helpers
- Development utilities

## Benefits of Modular Structure

1. **Logical Organization** - Related functionality grouped together
2. **Easier Navigation** - Find code by feature area
3. **Better Testing** - Test modules independently
4. **Clearer Dependencies** - See what depends on what
5. **Parallel Development** - Work on different modules simultaneously
6. **Easier Refactoring** - Change one module without affecting others

## Migration Strategy

1. Create module structure
2. Move functions to appropriate modules
3. Update imports and re-exports
4. Test that everything still works
5. Then begin thinning process

## File Size Estimates After Modularization

- `lib.rs`: ~50 lines (re-exports)
- `client/`: ~200 lines
- `sync/sliding_sync.rs`: ~400 lines
- `timeline/`: ~150 lines
- `rooms/`: ~300 lines
- `backup/`: ~200 lines
- `verification/sas.rs`: ~200 lines
- `common/`: ~100 lines

Total: Still ~1,600 lines but properly organized