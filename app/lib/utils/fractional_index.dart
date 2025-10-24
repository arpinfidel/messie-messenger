const _alphabet = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const _base = _alphabet.length;

int _charToIndex(String char) => _alphabet.indexOf(char);
String _indexToChar(int index) => _alphabet[index];

String _increment(String key) {
  var result = '';
  var carry = 1;
  for (var i = key.length - 1; i >= 0; i--) {
    var index = _charToIndex(key[i]) + carry;
    carry = index ~/ _base;
    result = _indexToChar(index % _base) + result;
  }
  if (carry > 0) {
    result = _indexToChar(carry) + result;
  }
  return result;
}

String _getMidpoint(String prev, String next) {
  if (prev.isEmpty && next.isEmpty) {
    return 'm';
  }
  if (prev.isEmpty) {
    var mid = '';
    for (var i = 0; i < next.length; i++) {
      final char = next[i];
      final index = _charToIndex(char);
      if (index > 0) {
        mid += _indexToChar(index ~/ 2);
        return mid;
      }
      mid += _alphabet[0];
    }
    return mid + _alphabet[_base ~/ 2];
  }
  if (next.isEmpty) {
    return _increment(prev);
  }

  var newKey = '';
  var i = 0;
  while (true) {
    final prevChar = i < prev.length ? prev[i] : _alphabet[0];
    final nextChar = i < next.length ? next[i] : _alphabet[_base - 1];

    final prevIndex = _charToIndex(prevChar);
    final nextIndex = _charToIndex(nextChar);

    if (prevIndex == nextIndex) {
      newKey += prevChar;
      i++;
    } else if (nextIndex - prevIndex == 1) {
      newKey += prevChar;
      i++;
      newKey += _alphabet[_base ~/ 2];
      return newKey;
    } else {
      newKey += _indexToChar((prevIndex + nextIndex) ~/ 2);
      return newKey;
    }
  }
}

/// Generate a lexicographically sortable position key between two neighbors.
String generatePosition(String? prevPosition, String? nextPosition) {
  final p = prevPosition ?? '';
  final n = nextPosition ?? '';
  return _getMidpoint(p, n);
}

