Matrix data flow (revamped)

- MatrixViewModel: orchestrates lifecycle (session, client start, crypto), exposes public API without direct SDK reads.
- MatrixDataStore: in-memory source of truth for rooms, events per room, and pagination tokens; also stores current user info.
- MatrixDataLayer: the only layer that talks to the Matrix SDK for reads; converts SDK events to RepoEvent and populates MatrixDataStore.
- MatrixTimelineService: computes derived outputs (room previews, message lists) strictly from MatrixDataStore; triggers MatrixDataLayer to fetch when needed.
- MatrixEventBinder: subscribes to SDK events and routes them through MatrixTimelineService → MatrixDataLayer to update the store, then refreshes views.

Notes

- Room list and previews are computed from MatrixDataStore; we no longer traverse SDK timelines in view models/services.
- Pagination state (backward token) is kept per room in MatrixDataStore and updated only by MatrixDataLayer.
- Public APIs like getRoomMessages/loadOlderMessages use MatrixDataLayer for IO and MatrixDataStore for computation/mapping.
