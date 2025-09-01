export class LRUCache<K, V> {
  private cache: Map<K, V>;
  private readonly maxSize: number;

  constructor(maxSize: number = 100) {
    this.cache = new Map();
    this.maxSize = maxSize;
  }

  get(key: K): V | undefined {
    if (!this.cache.has(key)) return undefined;

    // Get the value and refresh its position in the cache
    const value = this.cache.get(key)!;
    this.cache.delete(key);
    this.cache.set(key, value);
    return value;
  }

  set(key: K, value: V): void {
    // If key exists, remove it first to update its position
    if (this.cache.has(key)) {
      this.cache.delete(key);
    }
    // If cache is at capacity, remove the least recently used item
    else if (this.cache.size >= this.maxSize) {
      const firstKey = this.cache.keys().next();
      if (!firstKey.done) {
        this.cache.delete(firstKey.value);
      }
    }

    this.cache.set(key, value);
  }

  clear(): void {
    this.cache.clear();
  }

  delete(key: K): boolean {
    return this.cache.delete(key);
  }

  has(key: K): boolean {
    return this.cache.has(key);
  }
}
