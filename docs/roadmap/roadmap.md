Messie Messenger Product Roadmap (Draft)
=======================================

Purpose
-------
Provide a shared view of where the product is headed so engineering, design, and product can coordinate scope, dependencies, and discovery. This roadmap synthesizes module-specific plans (Matrix, Email, Todo, Shared platform) into a single narrative focused on experience outcomes rather than ticket IDs.

Guiding Themes
--------------
- **One desk for everything**: Matrix chat, email, and todos should feel like facets of a single workspace with consistent design language and interaction patterns.
- **Reliability before reach**: Ship stabilizing improvements and foundational refactors before layering advanced features or new surfaces.
- **Intelligent assistance**: Invest in AI-powered guidance (filters, summaries, search) once core data pipelines are trustworthy.

Horizon View
------------

**Now — Stabilize the foundation (0–2 sprints)**
- Frontend architecture realigned to MVVM so views stay declarative and stateful logic lives in view models (Email, Todo, Unified Timeline).
- Email reading experience hardened: dependable login, mailbox hydration, and rich body rendering with sanitization guardrails.
- Matrix baseline reliability: resolve avatar fetching issues, unblock concurrent sync requests, and shore up caching to prevent message gaps.
- Matrix developer velocity: complete testability refactors and auditing of message delivery edge cases.

**Next — Reach feature parity across core modules (2–4 sprints)**
- Email interaction loop: reply/reply-all/forward flows, formatting primitives, attachment handling, and persistence so history survives refreshes.
- Email pagination and caching to support large inboxes without regressions in unread counts.
- Todo workspace polish: unified command surface for create/update/reorder, contextual menus for quick actions, timeline badges for due status.
- Matrix engagement tooling: mute/pin controls, notification hygiene, and refinements to room loading performance.

**Later — Expand intelligent and connected experiences (4+ sprints)**
- AI assistance: retrieval-augmented search, AI-generated filters, and transaction parsing to power future expense tracking.
- Expense tracker vertical: transform transaction insights into actionable timelines and cross-reference with email receipts.
- Calendar bridge: introduce shared scheduling views and integrate Todo deadlines with calendar surfaces.
- Search platform: shared indexing helpers and cross-module search entry points.
- Platform investments: structured settings, theming tokens, accessibility checklist adoption, and backend foundations to support multi-account futures.

Domain Snapshots
----------------
- **Matrix**: Focus on ergonomics (replies, reactions, pinning), bridge awareness, and encryption UX once existing reliability issues are cleared. Requires clear notification strategy across Matrix and bridged events.
- **Email**: Evolve from proxy MVP to full client by layering composer, pagination, attachment lifecycle, and eventual send strategy (SMTP bridge). HTML sanitization and attachment storage decisions remain open.
- **Todo**: Expand beyond desktop to mobile-ready interactions, realtime collaboration, and calendar-aware timelines. Offline-first behavior and conflict resolution need dedicated discovery.
- **Shared Platform**: Establish modular settings, unified notifications, theming system, and accessibility standards. Investigate offline caching boundaries and OS-level integration for future native shells.

Dependencies & Risks
--------------------
- MVVM refactor must land before major Todo or unified timeline work to avoid rework and inconsistent state management.
- Email composer and attachments depend on storage, persistence, and security decisions; align backend contracts before locking UI.
- AI-driven features require reliable data ingestion from Email and Matrix; defer discovery until pagination and persistence are stable.
- Calendar bridge and search investments compete for backend capacity—plan sequencing with infrastructure bandwidth in mind.

Milestones & Checkpoints
------------------------
- **Frontend alignment complete**: MVVM view models own network + state, with views binding only to exposed stores.
- **Email parity milestone**: users can read, compose, and manage attachments with responsive pagination.
- **Matrix reliability milestone**: avatar, sync, and caching regressions eliminated; telemetry shows target percentile latency.
- **Unified settings alpha**: global + module tabs, notification preferences, and theming tokens documented.
- **AI discovery complete**: validated scope for RAG search and expense tracker flows, ready for implementation.

Next Steps
----------
- Socialize this roadmap with module leads to confirm sequencing and surface missing prerequisites.
- Update individual module docs with revised timelines or new learnings, then link back here.
- Revisit horizons quarterly (or after major milestones) to adjust scope, add dates, or promote “Later” items into active planning.
