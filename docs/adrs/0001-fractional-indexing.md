# ADR 0001: Fractional Indexing for Todos

Summary
-------

Enable stable, conflict-free ordering of todo items by storing a string position key that can be rebalanced rarely and computed locally for inserts between two neighbors.

Problem
-------

Simple integer positions require shifting many rows on insert/reorder and create contention. We need fast inserts between items and predictable merges.

Proposal
--------

- Store a `position` column per item as a lexicographically sortable string (e.g., base-62 alphabet).
- To insert between `left` and `right`, generate a key strictly between them (e.g., midpoint algorithm).
- For prepend/append, generate keys smaller/greater than current extremes.
- Rebalance only when keys become too dense (rare); handled as a background maintenance task or opportunistically during edits.

Client API Shape
----------------

- Client computes `position` locally for reorder/insert operations and sends it with the item update/create request.
- Server validates and persists without global reindexing.

Data Model
----------

- Table: `todo_items`
  - `id` UUID/serial
  - `list_id` FK
  - `position` TEXT (indexed)
  - other fields (title, done, etc.)

Open Questions
--------------

- Alphabet and max key length policy.
- Rebalance trigger thresholds and batching.
- Cross-list moves semantics (retain vs regenerate positions).
