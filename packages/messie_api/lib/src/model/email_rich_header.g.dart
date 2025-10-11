// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_rich_header.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmailRichHeader extends EmailRichHeader {
  @override
  final String? from;
  @override
  final String? subject;
  @override
  final DateTime? date;
  @override
  final String? messageId;
  @override
  final String? inReplyTo;
  @override
  final BuiltList<String>? references;

  factory _$EmailRichHeader([void Function(EmailRichHeaderBuilder)? updates]) =>
      (EmailRichHeaderBuilder()..update(updates))._build();

  _$EmailRichHeader._(
      {this.from,
      this.subject,
      this.date,
      this.messageId,
      this.inReplyTo,
      this.references})
      : super._();
  @override
  EmailRichHeader rebuild(void Function(EmailRichHeaderBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailRichHeaderBuilder toBuilder() => EmailRichHeaderBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailRichHeader &&
        from == other.from &&
        subject == other.subject &&
        date == other.date &&
        messageId == other.messageId &&
        inReplyTo == other.inReplyTo &&
        references == other.references;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jc(_$hash, messageId.hashCode);
    _$hash = $jc(_$hash, inReplyTo.hashCode);
    _$hash = $jc(_$hash, references.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmailRichHeader')
          ..add('from', from)
          ..add('subject', subject)
          ..add('date', date)
          ..add('messageId', messageId)
          ..add('inReplyTo', inReplyTo)
          ..add('references', references))
        .toString();
  }
}

class EmailRichHeaderBuilder
    implements Builder<EmailRichHeader, EmailRichHeaderBuilder> {
  _$EmailRichHeader? _$v;

  String? _from;
  String? get from => _$this._from;
  set from(String? from) => _$this._from = from;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  DateTime? _date;
  DateTime? get date => _$this._date;
  set date(DateTime? date) => _$this._date = date;

  String? _messageId;
  String? get messageId => _$this._messageId;
  set messageId(String? messageId) => _$this._messageId = messageId;

  String? _inReplyTo;
  String? get inReplyTo => _$this._inReplyTo;
  set inReplyTo(String? inReplyTo) => _$this._inReplyTo = inReplyTo;

  ListBuilder<String>? _references;
  ListBuilder<String> get references =>
      _$this._references ??= ListBuilder<String>();
  set references(ListBuilder<String>? references) =>
      _$this._references = references;

  EmailRichHeaderBuilder() {
    EmailRichHeader._defaults(this);
  }

  EmailRichHeaderBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _from = $v.from;
      _subject = $v.subject;
      _date = $v.date;
      _messageId = $v.messageId;
      _inReplyTo = $v.inReplyTo;
      _references = $v.references?.toBuilder();
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailRichHeader other) {
    _$v = other as _$EmailRichHeader;
  }

  @override
  void update(void Function(EmailRichHeaderBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmailRichHeader build() => _build();

  _$EmailRichHeader _build() {
    _$EmailRichHeader _$result;
    try {
      _$result = _$v ??
          _$EmailRichHeader._(
            from: from,
            subject: subject,
            date: date,
            messageId: messageId,
            inReplyTo: inReplyTo,
            references: _references?.build(),
          );
    } catch (_) {
      late String _$failedField;
      try {
        _$failedField = 'references';
        _references?.build();
      } catch (e) {
        throw BuiltValueNestedFieldError(
            r'EmailRichHeader', _$failedField, e.toString());
      }
      rethrow;
    }
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
