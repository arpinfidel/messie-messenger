## Agent Instructions (repo-local)

These instructions apply to any AI agent working in this repo.

### Project Overview

Messie Messenger is the backend and reference implementation for the Messie ecosystem. It provides a multi-channel productivity hub combining Matrix chat, IMAP email, and collaborative todos.

### Architecture

- Go (Chi) backend
- Svelte+Vite frontend (reference implementation, being replaced by FluffyChat Flutter client)
- Flutter mobile app with shared Rust core via `flutter_rust_bridge`
- Docker Compose orchestrated
- Includes WhatsApp bridge (mautrix-whatsapp), local Synapse Matrix homeserver support, Jira sync utility

### Product Direction

- `messie-messenger` is the backend; `fluffychat` is the primary client
- The Messie Svelte frontend is reference material; new client work happens in the FluffyChat Flutter fork
- Todo direction: todos as a first-class surface with list/detail flows, item CRUD, collaborators, and eventual unified timeline/calendar integration

### Dev Services

- Messie dev services usually start from `/workspace/dev-messie-up.sh`
- After changing backend code, restart or rebuild the live backend service before validating behavior against running logs or HTTP responses; do not assume repo changes are live until the container/process has been restarted on the updated code

### Git

- Branch: `master`
- For every new issue or feature, create a new feature branch from `master`
- Make small checkpoint commits; amend after user runtime/device feedback
- Do not commit directly to `master`
- Squash merge completed feature branches into `master` when user approves
