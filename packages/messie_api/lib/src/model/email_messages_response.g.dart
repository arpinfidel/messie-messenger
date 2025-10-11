// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_messages_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmailMessagesResponse extends EmailMessagesResponse {
  @override
  final BuiltList<EmailMessageHeader>? messages;
  @override
  final int? unreadCount;

  factory _$EmailMessagesResponse(
          [void Function(EmailMessagesResponseBuilder)? updates]) =>
      (EmailMessagesResponseBuilder()..update(updates))._build();

  _$EmailMessagesResponse._({this.messages, this.unreadCount}) : super._();
  @override
  EmailMessagesResponse rebuild(
          void Function(EmailMessagesResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailMessagesResponseBuilder toBuilder() =>
      EmailMessagesResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailMessagesResponse &&
        messages == other.messages &&
        unreadCount == other.unreadCount;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, messages.hashCode);
    _$hash = $jc(_$hash, unreadCount.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmailMessagesResponse')
          ..add('messages', messages)
          ..add('unreadCount', unreadCount))
        .toString();
  }
}

class EmailMessagesResponseBuilder
    implements Builder<EmailMessagesResponse, EmailMessagesResponseBuilder> {
  _$EmailMessagesResponse? _$v;

  ListBuilder<EmailMessageHeader>? _messages;
  ListBuilder<EmailMessageHeader> get messages =>
      _$this._messages ??= ListBuilder<EmailMessageHeader>();
  set messages(ListBuilder<EmailMessageHeader>? messages) =>
      _$this._messages = messages;

  int? _unreadCount;
  int? get unreadCount => _$this._unreadCount;
  set unreadCount(int? unreadCount) => _$this._unreadCount = unreadCount;

  EmailMessagesResponseBuilder() {
    EmailMessagesResponse._defaults(this);
  }

  EmailMessagesResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _messages = $v.messages?.toBuilder();
      _unreadCount = $v.unreadCount;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailMessagesResponse other) {
    _$v = other as _$EmailMessagesResponse;
  }

  @override
  void update(void Function(EmailMessagesResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmailMessagesResponse build() => _build();

  _$EmailMessagesResponse _build() {
    _$EmailMessagesResponse _$result;
    try {
      _$result = _$v ??
          _$EmailMessagesResponse._(
            messages: _messages?.build(),
            unreadCount: unreadCount,
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'messages';
        _messages?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'EmailMessagesResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
