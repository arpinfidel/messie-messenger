# Fractional Indexing for List Ordering

We use fractional indexing (also called lexicographic position keys) to maintain the order of todo items without needing global renumbering jobs.

## How it works

Each item has a position key, a string generated from a fixed alphabet (e.g., base-62 0-9a-zA-Z).

Items are ordered by the lexicographic order of their position keys.

To insert between two items, we generate a new key that sorts strictly between their keys:

e.g. between "a" and "b" → "am"

between "am" and "an" → "amf", and so on.

If inserting at the start or end, we generate a key before the first or after the last.

## Why this approach

No renumbering required: There is always infinite “space” between two keys by extending the string.

Efficient updates: Reordering only updates the moved item’s key, never the whole list.

Concurrency-friendly: Works well with multi-user or offline edits since each new key is unique and totally ordered.

Deterministic ordering: Queries simply ORDER BY position.

## Trade-offs

Keys can grow longer if many inserts happen in the same narrow gap, but this growth is localized and typically stays small (a handful of characters).

Slightly more complex key generation logic (done in application code).

Slight storage overhead compared to simple integers.
