# Todo Microservice

This is a Go-based microservice for managing todo lists and todo items.

## OpenAPI Specification and Code Generation

The API is defined using an OpenAPI 3.0 specification in `../docs/openapi.yaml`. Go server and client code is generated from this specification using `oapi-codegen`.

To regenerate the Go code after modifying `openapi.yaml`, run the following command from the `backend/todo-service` directory:

```bash
go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -package generated -generate types,chi-server -o api/generated/todo_api.go ../docs/openapi.yaml

## Database Migrations

We use `golang-migrate/migrate` for database migrations.

**Installation:**
```bash
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest
```

**Commands:**

*   **Create a new migration:**
    ```bash
    migrate create -ext sql -dir migrations -seq <migration_name>
    ```
    (e.g., `migrate create -ext sql -dir migrations -seq add_users_table`)

*   **Apply all up migrations:**
    ```bash
    migrate -path migrations -database "$DATABASE_URL" up
    ```

*   **Rollback the last migration:**
    ```bash
    migrate -path migrations -database "$DATABASE_URL" down 1
    ```

*   **Force a specific version (use with caution):**
    ```bash
    migrate -path migrations -database "$DATABASE_URL" force <version>
    ```

*   **View current migration status:**
    ```bash
    migrate -path migrations -database "$DATABASE_URL" status
    ```
```