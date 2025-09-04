```rust
- fetching new events from sdk is read as a "new event" and added to bottom of chat
- still 404
	resolveInternal
	AvatarResolver.ts:65:25
	resolve
	AvatarResolver.ts:32:20
	resolveAvatarMxc
	MatrixDataLayer.ts:479:43
	resolveRoomAvatar/urls<
	AvatarService.ts:71:62
	resolveRoomAvatar
	AvatarService.ts:71:41
	handleEvent/<
	MatrixTimelineService.ts:153:38
	emit
	MatrixDataLayer.ts:24:9
	handleMatrixMessages/<
	MatrixDataLayer.ts:392:29
	emit
	events.js:153:5
	emit
	typed-event-emitter.ts:89:22
	forSource2
	ReEmitter.ts:55:29
	emit
	events.js:158:7
	emit
	typed-event-emitter.ts:89:22
	forSource2
	ReEmitter.ts:55:29
	emit
	events.js:153:5
	emit
	typed-event-emitter.ts:89:22
	a
- avatar not reused?
```
