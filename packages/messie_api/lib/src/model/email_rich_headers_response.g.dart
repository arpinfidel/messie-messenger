// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_rich_headers_response.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmailRichHeadersResponse extends EmailRichHeadersResponse {
  @override
  final BuiltList<EmailRichHeader> messages;

  factory _$EmailRichHeadersResponse(
          [void Function(EmailRichHeadersResponseBuilder)? updates]) =>
      (EmailRichHeadersResponseBuilder()..update(updates))._build();

  _$EmailRichHeadersResponse._({required this.messages}) : super._();
  @override
  EmailRichHeadersResponse rebuild(
          void Function(EmailRichHeadersResponseBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailRichHeadersResponseBuilder toBuilder() =>
      EmailRichHeadersResponseBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailRichHeadersResponse && messages == other.messages;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, messages.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmailRichHeadersResponse')
          ..add('messages', messages))
        .toString();
  }
}

class EmailRichHeadersResponseBuilder
    implements
        Builder<EmailRichHeadersResponse, EmailRichHeadersResponseBuilder> {
  _$EmailRichHeadersResponse? _$v;

  ListBuilder<EmailRichHeader>? _messages;
  ListBuilder<EmailRichHeader> get messages =>
      _$this._messages ??= ListBuilder<EmailRichHeader>();
  set messages(ListBuilder<EmailRichHeader>? messages) =>
      _$this._messages = messages;

  EmailRichHeadersResponseBuilder() {
    EmailRichHeadersResponse._defaults(this);
  }

  EmailRichHeadersResponseBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _messages = $v.messages.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailRichHeadersResponse other) {
    _$v = other as _$EmailRichHeadersResponse;
  }

  @override
  void update(void Function(EmailRichHeadersResponseBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmailRichHeadersResponse build() => _build();

  _$EmailRichHeadersResponse _build() {
    _$EmailRichHeadersResponse _$result;
    try {
      _$result = _$v ??
          _$EmailRichHeadersResponse._(
            messages: messages.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'messages';
        messages.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'EmailRichHeadersResponse', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
