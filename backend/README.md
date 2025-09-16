# Todo Microservice

This is a Go-based microservice for managing todo lists and todo items.

## OpenAPI Specification and Code Generation

The API is defined using an OpenAPI 3.0 specification in `../docs/openapi.yaml`. Server stubs are generated with `oapi-codegen`.

To regenerate the Go code after modifying `openapi.yaml`, run from the `backend` directory:

```bash
go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen \
  -package generated -generate types,chi-server \
  -o api/generated/todo_api.go ../docs/openapi.yaml
```

Or use the repository Makefile from the project root:

```bash
make gen-be   # backend stubs
make gen      # backend + frontend
```

## Running locally

Set required environment variables and start the service:

```bash
export DATABASE_URL="postgres://user:password@localhost:5432/todo_db?sslmode=disable"
export JWT_SECRET="your-secret"
export PORT=8080
go run .
```

## Database schema (GORM AutoMigrate)

The service uses GORM AutoMigrate on startup to create/update the required tables (users, todo lists/items, collaborators). No manual SQL migration steps are required.
