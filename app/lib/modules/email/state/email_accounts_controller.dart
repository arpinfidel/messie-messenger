import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../services/email_account.dart';

const _kEmailAccountsKey = 'messie.email.accounts';

final emailAccountsProvider = FutureProvider<List<EmailAccountConfig>>((ref) async {
  const storage = FlutterSecureStorage();
  final raw = await storage.read(key: _kEmailAccountsKey);
  if (raw == null || raw.isEmpty) return const <EmailAccountConfig>[];
  try {
    final list = (jsonDecode(raw) as List).cast<Map>().map((e) => EmailAccountConfig.fromJson(e.cast<String, dynamic>())).toList();
    return list;
  } catch (_) {
    return const <EmailAccountConfig>[];
  }
});

final emailAccountsControllerProvider = Provider<EmailAccountsController>((ref) => EmailAccountsController(ref));

class EmailAccountsController {
  EmailAccountsController(this._ref);
  final Ref _ref;

  Future<void> addAccount(EmailAccountConfig config) async {
    const storage = FlutterSecureStorage();
    final existing = await _ref.read(emailAccountsProvider.future);
    final next = [...existing, config];
    final jsonList = next.map((e) => e.toJson()).toList();
    await storage.write(key: _kEmailAccountsKey, value: jsonEncode(jsonList));
    _ref.invalidate(emailAccountsProvider);
  }
}

