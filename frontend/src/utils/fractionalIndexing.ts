const ALPHABET = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz';
const BASE = ALPHABET.length;

function charToIndex(char: string): number {
  return ALPHABET.indexOf(char);
}

function indexToChar(index: number): string {
  return ALPHABET[index];
}

function increment(key: string): string {
  let result = '';
  let carry = 1;
  for (let i = key.length - 1; i >= 0; i--) {
    let index = charToIndex(key[i]) + carry;
    carry = Math.floor(index / BASE);
    result = indexToChar(index % BASE) + result;
  }
  if (carry > 0) {
    result = indexToChar(carry) + result;
  }
  return result;
}

function decrement(key: string): string {
  let result = '';
  let borrow = 0;
  for (let i = key.length - 1; i >= 0; i--) {
    let index = charToIndex(key[i]) - borrow;
    if (index < 0) {
      index += BASE;
      borrow = 1;
    } else {
      borrow = 0;
    }
    result = indexToChar(index) + result;
  }
  // Remove leading zeros if not the only character
  while (result.length > 1 && result[0] === ALPHABET[0]) {
    result = result.substring(1);
  }
  return result;
}

function getMidpoint(prev: string, next: string): string {
  if (prev === '' && next === '') {
    return 'm'; // Initial position for an empty list
  }
  if (prev === '') {
    // Insert at the beginning
    let mid = '';
    for (let i = 0; i < next.length; i++) {
      const char = next[i];
      const index = charToIndex(char);
      if (index > 0) {
        mid += indexToChar(Math.floor(index / 2));
        return mid;
      }
      mid += ALPHABET[0]; // Append '0' if current char is '0'
    }
    return mid + ALPHABET[Math.floor(BASE / 2)]; // Append 'm' if next is all '0's
  }
  if (next === '') {
    // Insert at the end
    return increment(prev);
  }

  // Insert between two existing keys
  let newKey = '';
  let i = 0;
  while (true) {
    const prevChar = prev[i] || ALPHABET[0];
    const nextChar = next[i] || ALPHABET[BASE - 1];

    const prevIndex = charToIndex(prevChar);
    const nextIndex = charToIndex(nextChar);

    if (prevIndex === nextIndex) {
      newKey += prevChar;
      i++;
    } else if (nextIndex - prevIndex === 1) {
      newKey += prevChar;
      i++;
      // Append 'm' (middle character) if no space, then fill with '0's
      newKey += ALPHABET[Math.floor(BASE / 2)];
      return newKey;
    } else {
      newKey += indexToChar(Math.floor((prevIndex + nextIndex) / 2));
      return newKey;
    }
  }
}

export function generatePosition(prevPosition: string | null, nextPosition: string | null): string {
  const p = prevPosition === null ? '' : prevPosition;
  const n = nextPosition === null ? '' : nextPosition;
  return getMidpoint(p, n);
}

export function getInitialPosition(): string {
  return generatePosition(null, null);
}
