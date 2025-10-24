import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../bridge/messie_bridge.dart';

final securityRepositoryProvider = Provider<SecurityRepository>((ref) {
  return SecurityRepository();
});

class SecurityRepository {
  Future<String?> generateRecoveryKey() async {
    final bootstrap = await rustSsssBootstrap(generateNewKey: true);
    if (bootstrap.isOk) {
      return bootstrap.data?.generatedRecoveryKey;
    }
    return null;
  }

  Future<bool> enableOnlineBackup({required bool generateNew}) async {
    final enable = await rustEnableOnlineBackup(generateNew: generateNew);
    return enable.isOk && (enable.data?.enabled == true);
  }

  Future<bool> recoverWithKey(String raw) async {
    var ok = await rustRecoverWithKey(recoveryKey: raw);
    if (ok.isOk) return true;
    if (raw.contains(' ')) {
      final compact = raw.replaceAll(RegExp('\\s+'), '');
      ok = await rustRecoverWithKey(recoveryKey: compact);
    }
    return ok.isOk;
  }
}

