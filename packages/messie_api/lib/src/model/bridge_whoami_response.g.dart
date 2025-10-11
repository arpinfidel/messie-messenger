// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_whoami_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$BridgeWhoamiResponse extends BridgeWhoamiResponse {
  @override
  final String? homeserver;
  @override
  final String? bridgeBot;
  @override
  final String? commandPrefix;
  @override
  final BridgeName? network;
  @override
  final BuiltList<BridgeLoginFlow>? loginFlows;
  @override
  final BuiltList<BridgeWhoamiLogin>? logins;

  factory _$BridgeWhoamiResponse(
          [void Function(BridgeWhoamiResponseBuilder)? updates]) =>
      (BridgeWhoamiResponseBuilder()..update(updates))._build();

  _$BridgeWhoamiResponse._(
      {this.homeserver,
      this.bridgeBot,
      this.commandPrefix,
      this.network,
      this.loginFlows,
      this.logins})
      : super._();
  @override
  BridgeWhoamiResponse rebuild(
          void Function(BridgeWhoamiResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeWhoamiResponseBuilder toBuilder() =>
      BridgeWhoamiResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeWhoamiResponse &&
        homeserver == other.homeserver &&
        bridgeBot == other.bridgeBot &&
        commandPrefix == other.commandPrefix &&
        network == other.network &&
        loginFlows == other.loginFlows &&
        logins == other.logins;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, homeserver.hashCode);
    _$hash = $jc(_$hash, bridgeBot.hashCode);
    _$hash = $jc(_$hash, commandPrefix.hashCode);
    _$hash = $jc(_$hash, network.hashCode);
    _$hash = $jc(_$hash, loginFlows.hashCode);
    _$hash = $jc(_$hash, logins.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeWhoamiResponse')
          ..add('homeserver', homeserver)
          ..add('bridgeBot', bridgeBot)
          ..add('commandPrefix', commandPrefix)
          ..add('network', network)
          ..add('loginFlows', loginFlows)
          ..add('logins', logins))
        .toString();
  }
}

class BridgeWhoamiResponseBuilder
    implements Builder<BridgeWhoamiResponse, BridgeWhoamiResponseBuilder> {
  _$BridgeWhoamiResponse? _$v;

  String? _homeserver;
  String? get homeserver => _$this._homeserver;
  set homeserver(String? homeserver) => _$this._homeserver = homeserver;

  String? _bridgeBot;
  String? get bridgeBot => _$this._bridgeBot;
  set bridgeBot(String? bridgeBot) => _$this._bridgeBot = bridgeBot;

  String? _commandPrefix;
  String? get commandPrefix => _$this._commandPrefix;
  set commandPrefix(String? commandPrefix) =>
      _$this._commandPrefix = commandPrefix;

  BridgeNameBuilder? _network;
  BridgeNameBuilder get network => _$this._network ??= BridgeNameBuilder();
  set network(BridgeNameBuilder? network) => _$this._network = network;

  ListBuilder<BridgeLoginFlow>? _loginFlows;
  ListBuilder<BridgeLoginFlow> get loginFlows =>
      _$this._loginFlows ??= ListBuilder<BridgeLoginFlow>();
  set loginFlows(ListBuilder<BridgeLoginFlow>? loginFlows) =>
      _$this._loginFlows = loginFlows;

  ListBuilder<BridgeWhoamiLogin>? _logins;
  ListBuilder<BridgeWhoamiLogin> get logins =>
      _$this._logins ??= ListBuilder<BridgeWhoamiLogin>();
  set logins(ListBuilder<BridgeWhoamiLogin>? logins) => _$this._logins = logins;

  BridgeWhoamiResponseBuilder() {
    BridgeWhoamiResponse._defaults(this);
  }

  BridgeWhoamiResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _homeserver = $v.homeserver;
      _bridgeBot = $v.bridgeBot;
      _commandPrefix = $v.commandPrefix;
      _network = $v.network?.toBuilder();
      _loginFlows = $v.loginFlows?.toBuilder();
      _logins = $v.logins?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeWhoamiResponse other) {
    _$v = other as _$BridgeWhoamiResponse;
  }

  @override
  void update(void Function(BridgeWhoamiResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeWhoamiResponse build() => _build();

  _$BridgeWhoamiResponse _build() {
    _$BridgeWhoamiResponse _$result;
    try {
      _$result = _$v ??
          _$BridgeWhoamiResponse._(
            homeserver: homeserver,
            bridgeBot: bridgeBot,
            commandPrefix: commandPrefix,
            network: _network?.build(),
            loginFlows: _loginFlows?.build(),
            logins: _logins?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'network';
        _network?.build();
        _$failedField = 'loginFlows';
        _loginFlows?.build();
        _$failedField = 'logins';
        _logins?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'BridgeWhoamiResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
