// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_message_header.dart';

// **************************************************************************
// BuiltValueGenerator
// **************************************************************************

class _$EmailMessageHeader extends EmailMessageHeader {
  @override
  final String? from;
  @override
  final String? subject;
  @override
  final DateTime? date;

  factory _$EmailMessageHeader(
          [void Function(EmailMessageHeaderBuilder)? updates]) =>
      (EmailMessageHeaderBuilder()..update(updates))._build();

  _$EmailMessageHeader._({this.from, this.subject, this.date}) : super._();
  @override
  EmailMessageHeader rebuild(
          void Function(EmailMessageHeaderBuilder) updates) =>
      (toBuilder()..update(updates)).build();

  @override
  EmailMessageHeaderBuilder toBuilder() =>
      EmailMessageHeaderBuilder()..replace(this);

  @override
  bool operator ==(Object other) {
    if (identical(other, this)) return true;
    return other is EmailMessageHeader &&
        from == other.from &&
        subject == other.subject &&
        date == other.date;
  }

  @override
  int get hashCode {
    var _$hash = 0;
    _$hash = $jc(_$hash, from.hashCode);
    _$hash = $jc(_$hash, subject.hashCode);
    _$hash = $jc(_$hash, date.hashCode);
    _$hash = $jf(_$hash);
    return _$hash;
  }

  @override
  String toString() {
    return (newBuiltValueToStringHelper(r'EmailMessageHeader')
          ..add('from', from)
          ..add('subject', subject)
          ..add('date', date))
        .toString();
  }
}

class EmailMessageHeaderBuilder
    implements Builder<EmailMessageHeader, EmailMessageHeaderBuilder> {
  _$EmailMessageHeader? _$v;

  String? _from;
  String? get from => _$this._from;
  set from(String? from) => _$this._from = from;

  String? _subject;
  String? get subject => _$this._subject;
  set subject(String? subject) => _$this._subject = subject;

  DateTime? _date;
  DateTime? get date => _$this._date;
  set date(DateTime? date) => _$this._date = date;

  EmailMessageHeaderBuilder() {
    EmailMessageHeader._defaults(this);
  }

  EmailMessageHeaderBuilder get _$this {
    final $v = _$v;
    if ($v != null) {
      _from = $v.from;
      _subject = $v.subject;
      _date = $v.date;
      _$v = null;
    }
    return this;
  }

  @override
  void replace(EmailMessageHeader other) {
    _$v = other as _$EmailMessageHeader;
  }

  @override
  void update(void Function(EmailMessageHeaderBuilder)? updates) {
    if (updates != null) updates(this);
  }

  @override
  EmailMessageHeader build() => _build();

  _$EmailMessageHeader _build() {
    final _$result = _$v ??
        _$EmailMessageHeader._(
          from: from,
          subject: subject,
          date: date,
        );
    replace(_$result);
    return _$result;
  }
}

// ignore_for_file: deprecated_member_use_from_same_package,type=lint
