# OpenID Token Verification Flow

## Overall Goal
To enable the client to authenticate with our todo server using their Matrix account via a short-lived OpenID token.

## Workflow

1.  **Client requests OpenID token from Homeserver:** The client, already logged into Matrix, will request a short-lived OpenID token from its Matrix Homeserver.
2.  **Client sends OpenID token to our backend:** The client will then send this OpenID token (along with the `matrix_server_name`) to a new authentication endpoint on our todo server.
3.  **Our backend validates token with Homeserver:** Our todo server will receive the OpenID token and `matrix_server_name`. It will then call the Matrix Homeserver's federation `userinfo` endpoint to validate the token.
4.  **Our backend issues its own session:** If the token is valid and the Matrix ID (`sub`) matches the `matrix_server_name`, our backend will consider the user authenticated and issue its own session token (e.g., a JWT) for our todo service.
5.  **Client receives our session token:** The client will receive this session token and use it for subsequent authenticated requests to our todo service.

## Implementation Steps

*   **Step 1: Document the plan.**
    *   Create or update `plan.md` with a detailed explanation of the OpenID token verification flow, including the "What you're building" and "How" sections, and the two main steps: "Client → Homeserver: request OpenID token" and "Your backend → Homeserver: validate token".
*   **Step 2: Analyze and update user schema for Matrix ID.**
    *   Examine the existing user schema in the backend to determine if it can accommodate a Matrix ID.
    *   If not, modify the user entity, repository, and potentially the database schema to include a field for Matrix ID.
*   **Step 3: Implement backend OpenID authentication endpoint.**
    *   Add a new authentication endpoint to the Go todo service. The exact route will be determined during implementation, but it will handle `POST` requests.
    *   This endpoint will receive the `access_token` and `matrix_server_name` from the client.
    *   It will then make an HTTP GET request to the Matrix Homeserver's federation `userinfo` endpoint (`https://<federation-base>/_matrix/federation/v1/openid/userinfo?access_token=<token>`) to validate the token.
    *   It will verify that the `sub` (Matrix ID) returned by the Homeserver ends with the `matrix_server_name`.
    *   Upon successful validation, it will issue a JWT for our todo service and return it to the client.
    *   Consider implementing the optional federation base resolver for arbitrary homeservers.
*   **Step 4: Implement client-side OpenID token request and backend communication.**
    *   Create a temporary placeholder for the todo module in the client.
    *   Within this placeholder, implement the logic to:
        *   Obtain the OpenID token from the `matrix-js-sdk` (or via raw HTTP if the SDK is not available/integrated).
        *   Send the `access_token` and `matrix_server_name` to our new backend endpoint.
        *   Receive and store the JWT issued by our backend for future authenticated requests to the todo service.
