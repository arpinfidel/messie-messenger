// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'bridge_login_step.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

const BridgeLoginStepTypeEnum _$bridgeLoginStepTypeEnum_displayAndWait =
    const BridgeLoginStepTypeEnum._('displayAndWait');
const BridgeLoginStepTypeEnum _$bridgeLoginStepTypeEnum_userInput =
    const BridgeLoginStepTypeEnum._('userInput');
const BridgeLoginStepTypeEnum _$bridgeLoginStepTypeEnum_cookies =
    const BridgeLoginStepTypeEnum._('cookies');
const BridgeLoginStepTypeEnum _$bridgeLoginStepTypeEnum_complete =
    const BridgeLoginStepTypeEnum._('complete');

BridgeLoginStepTypeEnum _$bridgeLoginStepTypeEnumValueOf(String name) {
  switch (name) {
    case 'displayAndWait':
      return _$bridgeLoginStepTypeEnum_displayAndWait;
    case 'userInput':
      return _$bridgeLoginStepTypeEnum_userInput;
    case 'cookies':
      return _$bridgeLoginStepTypeEnum_cookies;
    case 'complete':
      return _$bridgeLoginStepTypeEnum_complete;
    default:
      throw ArgumentError(name);
  }
}

final BuiltSet<BridgeLoginStepTypeEnum> _$bridgeLoginStepTypeEnumValues =
    BuiltSet<BridgeLoginStepTypeEnum>(const <BridgeLoginStepTypeEnum>[
  _$bridgeLoginStepTypeEnum_displayAndWait,
  _$bridgeLoginStepTypeEnum_userInput,
  _$bridgeLoginStepTypeEnum_cookies,
  _$bridgeLoginStepTypeEnum_complete,
]);

Serializer<BridgeLoginStepTypeEnum> _$bridgeLoginStepTypeEnumSerializer =
    _$BridgeLoginStepTypeEnumSerializer();

class _$BridgeLoginStepTypeEnumSerializer
    implements PrimitiveSerializer<BridgeLoginStepTypeEnum> {
  static const Map<String, Object> _toWire = const <String, Object>{
    'displayAndWait': 'display_and_wait',
    'userInput': 'user_input',
    'cookies': 'cookies',
    'complete': 'complete',
  };
  static const Map<Object, String> _fromWire = const <Object, String>{
    'display_and_wait': 'displayAndWait',
    'user_input': 'userInput',
    'cookies': 'cookies',
    'complete': 'complete',
  };

  @override
  final Iterable<Type> types = const <Type>[BridgeLoginStepTypeEnum];
  @override
  final String wireName = 'BridgeLoginStepTypeEnum';

  @override
  Object serialize(Serializers serializers, BridgeLoginStepTypeEnum object,
          {FullType specifiedType = FullType.unspecified}) =>
      _toWire[object.name] ?? object.name;

  @override
  BridgeLoginStepTypeEnum deserialize(
          Serializers serializers, Object serialized,
          {FullType specifiedType = FullType.unspecified}) =>
      BridgeLoginStepTypeEnum.valueOf(
          _fromWire[serialized] ?? (serialized is String ? serialized : ''));
}

class _$BridgeLoginStep extends BridgeLoginStep {
  @override
  final OneOf oneOf;

  factory _$BridgeLoginStep([void Function(BridgeLoginStepBuilder)? updates]) =>
      (BridgeLoginStepBuilder()..update(updates))._build();

  _$BridgeLoginStep._({required this.oneOf}) : super._();
  @override
  BridgeLoginStep rebuild(void Function(BridgeLoginStepBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  BridgeLoginStepBuilder toBuilder() => BridgeLoginStepBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is BridgeLoginStep && oneOf == other.oneOf;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, oneOf.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'BridgeLoginStep')
          ..add('oneOf', oneOf))
        .toString();
  }
}

class BridgeLoginStepBuilder
    implements Builder<BridgeLoginStep, BridgeLoginStepBuilder> {
  _$BridgeLoginStep? _$v;

  OneOf? _oneOf;
  OneOf? get oneOf => _$this._oneOf;
  set oneOf(OneOf? oneOf) => _$this._oneOf = oneOf;

  BridgeLoginStepBuilder() {
    BridgeLoginStep._defaults(this);
  }

  BridgeLoginStepBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _oneOf = $v.oneOf;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(BridgeLoginStep other) {
    _$v = other as _$BridgeLoginStep;
  }

  @override
  void update(void Function(BridgeLoginStepBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  BridgeLoginStep build() => _build();

  _$BridgeLoginStep _build() {
    final _$result = _$v ??
        _$BridgeLoginStep._(
          oneOf: BuiltValueNullFieldError.checkNotNull(
              oneOf, r'BridgeLoginStep', 'oneOf'),
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
