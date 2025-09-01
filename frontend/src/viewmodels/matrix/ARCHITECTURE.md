Matrix data flow (revamped)

- MatrixViewModel: orchestrates lifecycle (session, client start, crypto), exposes public API without direct SDK reads.
- MatrixDataLayer: the only layer that talks to the Matrix SDK and IndexedDB. It exposes queries for rooms and events and handles all persistence.
- MatrixTimelineService: computes derived outputs (room previews, message lists) by querying MatrixDataLayer; triggers MatrixDataLayer to fetch when needed.
- MatrixEventBinder: subscribes to SDK events and routes them through MatrixTimelineService → MatrixDataLayer, then refreshes views.

Notes

- Room list and previews are computed by querying MatrixDataLayer; we no longer traverse SDK timelines in view models/services.
- Pagination state (backward token) is kept per room in IndexedDB and updated only by MatrixDataLayer.
- Public APIs like getRoomMessages/loadOlderMessages use MatrixDataLayer for both IO and computation/mapping.
