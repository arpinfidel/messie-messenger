import 'package:flutter_test/flutter_test.dart';

import 'package:messie_app/main.dart';

void main() {
  group('MatrixSession', () {
    test('copyWith replaces provided fields', () {
      const original = MatrixSession(
        homeserverUrl: 'https://example.org',
        userId: '@user:example.org',
        accessToken: 'abc123',
        deviceId: 'DEVICE1',
      );

      final updated = original.copyWith(accessToken: 'def456', deviceId: 'DEVICE2');

      expect(updated.homeserverUrl, original.homeserverUrl);
      expect(updated.userId, original.userId);
      expect(updated.accessToken, 'def456');
      expect(updated.deviceId, 'DEVICE2');
    });
  });
}
