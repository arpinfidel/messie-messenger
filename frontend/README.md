## Frontend Features (moved from root README)

- Matrix-first messaging – A dedicated Matrix view model handles session restoration, client bootstrapping, crypto, notifications, room timelines, and read receipts, exposing data as timeline items consumed by the UI.
- Email aggregation without OAuth – Users provide IMAP host, port, and app password from the Email settings tab to fetch headers; the backend signs in via TLS and exposes aggregate thread listings and detailed headers.
- Todo lists and items – Authenticated users can create, read, update, and delete lists and items; fractional indexing keeps ordering stable and todos surface in the shared timeline.
- Unified timeline & detail panes – Items from Matrix, Email, and Todo modules appear in a unified timeline with a responsive two-pane layout and contextual settings.
- Cloud-auth bridge for JWT issuance – Exchanges a Matrix OpenID token for a backend JWT and persists it for authenticated API calls.

## Generating the API Client

To interact with the backend API, you need to generate the TypeScript client code. This client is generated using `openapi-generator-cli` from the OpenAPI specification.

### Prerequisites

- **Java Development Kit (JDK)**: `openapi-generator-cli` requires Java to run. Ensure you have a JDK installed (version 8 or higher is recommended). You can download it from [Oracle](https://www.oracle.com/java/technologies/downloads/) or use OpenJDK.

### Installation

If you don't have `openapi-generator-cli` installed globally, you can install it using npm:

```bash
npm install -g @openapitools/openapi-generator-cli
```

### Generating the Client

Once `openapi-generator-cli` is installed, navigate to the `frontend` directory and run the following command to generate the client:

```bash
openapi-generator-cli generate -i ../docs/openapi.yaml -g typescript-fetch -o src/api/generated
```

This command will:

- Read the OpenAPI specification from `../docs/openapi.yaml`.
- Generate a TypeScript client using the `typescript-fetch` generator.
- Output the generated code into the `src/api/generated` directory.

Alternatively, from the repository root you can use the Makefile targets:

```bash
make gen-fe   # regenerate frontend client
make gen      # backend + frontend
```
