# Messie UI Feature Reference

This document captures the current behavior of the Svelte front-end so the experience can be replicated in another stack. It focuses on concrete UI features, user flows, and notable edge cases.

## Application Shell & Navigation

- The root layout fills the viewport (`h-screen`) and switches between a two-column split and a single-column stack depending on the computed `DeviceProfile.supportsSplitLayout`. On wide displays, the unified timeline stays on the left and the detail panel stays open on the right; on narrow displays, selecting an item replaces the timeline until the detail view is closed. The app also registers synthetic browser history entries to support back-button navigation when the detail view is stacked. 【F:frontend/src/App.svelte†L27-L90】【F:frontend/src/App.svelte†L214-L245】
- Hardware/back button handlers are wired so that closing the detail view, dismissing the settings popup, and hiding the forgot-password flow consume a back navigation event instead of exiting the app. 【F:frontend/src/App.svelte†L92-L132】
- `messie-open-room` custom DOM events allow deep-linking into Matrix rooms by ID. When such an event is dispatched, the app finds the matching timeline item and selects it. 【F:frontend/src/App.svelte†L164-L170】
- Overlays are used for global states: a full-screen Matrix login/forgot-password surface when the homeserver session is missing, toast notifications when the email bridge fails, and an inline badge showing email mailbox refresh progress. Developer settings can optionally expose a floating build timestamp chip. 【F:frontend/src/App.svelte†L260-L312】

## Unified Timeline (Left Pane)

- The timeline aggregates Matrix rooms, email threads, todo lists, calendar entries, and other message-like sources exposed by the view model. It subscribes to stores for loading state, module-specific progress labels, search text, filter selection, and the sorted item list. 【F:frontend/src/views/shared/UnifiedTimeline.svelte†L43-L132】
- Users can multi-select items with modifier keys, shift+click, or long-press on touch. Selection state drives a contextual toolbar that reports the total number of selected items, the number of Matrix rooms in the selection, and feedback after bulk operations. Actions include “select all visible,” “mute selected rooms” (async with success/error toast), and “clear selection.” 【F:frontend/src/views/shared/UnifiedTimeline.svelte†L171-L404】
- A floating “Create” button opens a popup menu (currently for creating a todo list) and shows success/error banners based on the creation lifecycle. 【F:frontend/src/views/shared/UnifiedTimeline.svelte†L418-L456】【F:frontend/src/views/shared/UnifiedTimeline.svelte†L306-L318】
- Search and filtering controls live above the list. The search box pushes text into the view model, and a filter modal allows switching among source categories defined in `TIMELINE_SOURCE_FILTERS` (Matrix, Matrix bridges, Email, Todo, etc.). 【F:frontend/src/views/shared/UnifiedTimeline.svelte†L320-L327】【F:frontend/src/views/shared/UnifiedTimeline.svelte†L472-L563】【F:frontend/src/config/timelineSources.ts†L1-L55】
- Loading and empty states include module-specific progress text, an inbox-themed empty illustration, and an inline loading bar pinned to the bottom of the pane. 【F:frontend/src/views/shared/UnifiedTimeline.svelte†L169-L331】【F:frontend/src/views/shared/UnifiedTimeline.svelte†L512-L543】【F:frontend/src/views/shared/UnifiedTimeline.svelte†L569-L577】
- Each timeline row supports keyboard activation, click, and touch long-press. Items render avatars (image or emoji fallback), unread badges, truncated descriptions, and formatted timestamps that adapt by day/year. Selected rows gain a blue accent border. 【F:frontend/src/views/shared/timeline/GenericTimelineItem.svelte†L7-L216】

## Detail Panel (Right Pane)

The detail region switches among several specialized surfaces based on the selected timeline item type. 【F:frontend/src/views/shared/DetailPanel.svelte†L15-L32】

### Matrix Conversations

- The header displays the room title, message count, a close button (for stacked layouts), an overflow menu that can mute/unmute the room with async state handling, and a debug modal that lists raw room member data. 【F:frontend/src/views/matrix/components/RoomHeader.svelte†L8-L116】【F:frontend/src/views/matrix/components/RoomHeader.svelte†L133-L170】
- Message lists stream from the Matrix view model. The component manages session lifecycles per room, fetching the initial timeline, progressively loading older batches when the user scrolls near the top, and keeping scroll position stable when history is prepended. 【F:frontend/src/views/matrix/MatrixDetail.svelte†L29-L312】
- Real-time updates append in-place: repository events are mapped to message models, inserted chronologically, and optionally trigger auto-scroll if the user is already at the bottom. Otherwise an unread counter appears in the “Jump to latest” button. 【F:frontend/src/views/matrix/MatrixDetail.svelte†L318-L418】【F:frontend/src/views/matrix/MatrixDetail.svelte†L544-L577】
- Message bubbles support grouped avatars, sender labels, reply previews, inline images with a lightbox, file download chips, edit badges, and WhatsApp-style read receipts (single/double check). Context menus expose reply and edit actions, plus an edit-history popover for prior versions. 【F:frontend/src/views/matrix/components/MessageItem.svelte†L18-L241】【F:frontend/src/views/matrix/components/MessageItem.svelte†L279-L413】【F:frontend/src/views/matrix/components/MessageItem.svelte†L436-L501】
- Composing supports replies, inline editing, attachments, and keyboard shortcuts. The input bar shows reply/edit banners, opens a popup menu for picking media or files, prevents sending while busy, and submits on Enter (Shift+Enter for newline). Attachment previews sit above the input and can be cleared. 【F:frontend/src/views/matrix/MatrixDetail.svelte†L192-L215】【F:frontend/src/views/matrix/MatrixDetail.svelte†L600-L669】【F:frontend/src/views/matrix/components/MessageInput.svelte†L8-L141】【F:frontend/src/views/matrix/MatrixDetail.svelte†L696-L716】
- Mobile UX tweaks include disabling autofocus on phones/tablets, registering custom back-button behavior for the image lightbox, and revealing a floating jump-to-bottom control when the user scrolls away from the latest messages. 【F:frontend/src/views/matrix/MatrixDetail.svelte†L67-L80】【F:frontend/src/views/matrix/MatrixDetail.svelte†L139-L167】【F:frontend/src/views/matrix/MatrixDetail.svelte†L332-L359】

### Email Threads

- The email surface displays thread metadata (source mailbox label, subject, snippet) and per-message cards within the thread. It surfaces mailbox refresh states, connection errors, and generic loading placeholders using the email view model stores. 【F:frontend/src/views/email/EmailView.svelte†L15-L63】【F:frontend/src/views/email/EmailView.svelte†L65-L103】

### Todo Lists

- Todo details allow inline editing of list title/description, toggling completion, keyboard-driven quick add (Enter to add), and manual reordering with hover controls. Opening an item reveals editable description and due date fields that save on blur. The component also flushes pending writes when the tab becomes hidden. 【F:frontend/src/views/todo/TodoDetail.svelte†L8-L130】【F:frontend/src/views/todo/TodoDetail.svelte†L200-L298】

### Calendar Events

- Calendar entries currently show a simple read-only card with basic metadata and a close control. 【F:frontend/src/views/CalendarDetail.svelte†L13-L27】

## Settings & Account Surfaces

- The settings popup is a modal with a vertical tab list. Tabs currently host Matrix, Cloud Auth, Email, and Developer panels. 【F:frontend/src/views/shared/SettingsPopup.svelte†L5-L40】【F:frontend/src/App.svelte†L249-L258】
- Matrix settings let users store a recovery key, adjust per-room notification cooldown in seconds (persisted in milliseconds), and initiate SAS device verification, which opens a dedicated modal. 【F:frontend/src/views/matrix/MatrixSettingsTab.svelte†L1-L48】
- Cloud Auth integrates with the Matrix OpenID flow to authenticate against the Todo service; the UI shows a single CTA button with loading/error states and surfaces the current auth status. 【F:frontend/src/views/auth/CloudAuthTab.svelte†L1-L38】
- The Email tab presents an IMAP credential form, status indicators (“Connecting…”, “Refreshing…”, success/error banners), manual mailbox refresh, and logout controls. 【F:frontend/src/views/email/EmailLoginTab.svelte†L15-L116】
- Developer settings expose toggles for enabling the Eruda debugging console and revealing the build timestamp overlay. 【F:frontend/src/views/settings/DeveloperSettingsTab.svelte†L7-L53】【F:frontend/src/App.svelte†L308-L312】

## Authentication Flows

- Matrix login is handled in a full-screen modal with homeserver, username, and password fields. Credentials are persisted to `localStorage` for convenience. A “Forgot password?” link opens the password-reset workflow. 【F:frontend/src/views/matrix/MatrixLogin.svelte†L5-L66】【F:frontend/src/views/matrix/MatrixLogin.svelte†L68-L105】
- The password-reset flow handles both the initial email request and the redirected reset confirmation in the same component. It reads parameters from the URL, stores the `client_secret` for later use, and provides step-specific messaging. 【F:frontend/src/views/matrix/MatrixForgotPassword.svelte†L1-L123】【F:frontend/src/views/matrix/MatrixForgotPassword.svelte†L124-L207】
- Email integration has its own credential store and mailbox refresh UI within the settings tab, while mailbox refresh status is also surfaced globally beside the timeline. 【F:frontend/src/views/email/EmailLoginTab.svelte†L15-L116】【F:frontend/src/App.svelte†L302-L305】

## Notifications & Status Indicators

- Toast-like overlays appear in the bottom corners: email connection errors display as a red badge, mailbox refresh shows a dark chip, and timeline operations emit inline toasts inside the timeline column. 【F:frontend/src/App.svelte†L296-L305】【F:frontend/src/views/shared/UnifiedTimeline.svelte†L306-L318】
- Within Matrix conversations, jump-to-bottom and unread counters indicate unseen activity; message read receipts change icon color once other members have caught up. 【F:frontend/src/views/matrix/MatrixDetail.svelte†L33-L64】【F:frontend/src/views/matrix/components/MessageItem.svelte†L312-L349】

## Responsive & Device-Specific Considerations

- Device profile detection feeds both the master-detail layout switch and Matrix input autofocus logic, ensuring phones rely on stacked navigation while larger screens stay split. 【F:frontend/src/App.svelte†L33-L147】【F:frontend/src/views/matrix/MatrixDetail.svelte†L67-L80】
- Touch interactions get long-press selection in the timeline and popstate hooks for closing detail views, improving usability on mobile. 【F:frontend/src/views/shared/timeline/GenericTimelineItem.svelte†L38-L93】【F:frontend/src/App.svelte†L175-L188】

