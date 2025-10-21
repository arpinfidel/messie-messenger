import 'dart:isolate';

import 'messie_bridge_v2.dart' as v2;

extension MessieV2ClientHandleExt on int {
  ({bool success, int handle}) openTimeline(String roomId) =>
      v2.timelineOpen(clientHandle: this, roomId: roomId);

  List<String> listJoinedRooms() =>
      v2.clientListJoinedRooms(clientHandle: this);

  bool sendText(String roomId, String body, {String? replyTo}) =>
      v2.roomSendText(clientHandle: this, roomId: roomId, body: body, replyTo: replyTo);

  bool markReadUpTo(String roomId, String eventId) =>
      v2.roomMarkReadUpTo(clientHandle: this, roomId: roomId, eventId: eventId);

  int ssCreate({int pollTimeoutMs = 0, int networkTimeoutMs = 0, bool enableE2ee = true, bool enableToDevice = true}) =>
      v2.ssCreate(clientHandle: this, pollTimeoutMs: pollTimeoutMs, networkTimeoutMs: networkTimeoutMs, enableE2ee: enableE2ee, enableToDevice: enableToDevice);

  bool ssStart({required int ssHandle, required SendPort port}) =>
      v2.ssStart(ssHandle: ssHandle, port: port.nativePort);

  bool ssExpire({required int ssHandle}) => v2.ssExpireSession(ssHandle: ssHandle);
}

extension MessieV2TimelineHandleExt on int {
  bool startStreaming(SendPort port) => v2.timelineStartStreaming(timelineHandle: this, port: port.nativePort);
  bool loadBackward(int limit) => v2.timelineLoadBackward(timelineHandle: this, limit: limit);
}
