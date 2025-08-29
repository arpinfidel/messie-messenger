## Generating the API Client

To interact with the backend API, you need to generate the TypeScript client code. This client is generated using `openapi-generator-cli` from the OpenAPI specification.

### Prerequisites

-   **Java Development Kit (JDK)**: `openapi-generator-cli` requires Java to run. Ensure you have a JDK installed (version 8 or higher is recommended). You can download it from [Oracle](https://www.oracle.com/java/technologies/downloads/) or use OpenJDK.

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
-   Read the OpenAPI specification from `../docs/openapi.yaml`.
-   Generate a TypeScript client using the `typescript-fetch` generator.
-   Output the generated code into the `src/api/generated` directory.
