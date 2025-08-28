# Todo Microservice

This is a Go-based microservice for managing todo lists and todo items.

## OpenAPI Specification and Code Generation

The API is defined using an OpenAPI 3.0 specification in `api/openapi.yaml`. Go server and client code is generated from this specification using `oapi-codegen`.

To regenerate the Go code after modifying `openapi.yaml`, run the following command from the `backend/todo-service` directory:

```bash
go run github.com/oapi-codegen/oapi-codegen/v2/cmd/oapi-codegen -package generated -generate types,chi-server -o api/generated/todo_api.go api/openapi.yaml
```