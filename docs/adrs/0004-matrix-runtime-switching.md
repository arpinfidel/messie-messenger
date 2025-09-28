# 0004: Matrix Runtime Switching Contract

- Status: Accepted
- Date: 2024-05-13

## Context

- We currently rely solely on `matrix-js-sdk` when running inside Capacitor and the browser.
- Android will ship a native Matrix Rust SDK binding that must coexist with the existing JS runtime for web builds and as a fallback on devices that cannot load the native binary.
- Downstream view-models (e.g. `MatrixViewModel`, `MatrixMessagingService`) expect a stable API surface and lifecycle semantics regardless of the runtime that powers the client/crypto stack.

## Decision

We define a runtime switching contract that lives in TypeScript alongside the matrix view-models. The contract introduces:

1. **Runtime capability probing** – a `MatrixRuntimeDiscovery` component reports the available runtime (`'js'`, `'native'`, or `'auto'`) based on platform, feature flags, and bridge availability.
2. **Adapter interfaces** – `MatrixClientAdapter` and `MatrixCryptoAdapter` describe the minimal API used by the rest of the app. Both runtimes MUST implement these interfaces so the selector can swap implementations transparently.
3. **Lifecycle hooks** – the contract codifies `init`, `start`, `stop`, and `dispose` expectations, including how session state, push registration, and secret storage are handled across transitions.
4. **Unified selector** – `MatrixRuntimeSelector` owns choosing and initialising the runtime. It exposes telemetry hooks to record the selected runtime and any fallback paths.

The TypeScript interfaces live in `frontend/src/viewmodels/matrix/core/runtime/MatrixRuntimeTypes.ts` and are the single source of truth for the adapter API. Any new feature must extend these interfaces to remain runtime-agnostic.

## Consequences

- Runtime-dependent code lives behind a stable contract, so Matrix view-models and services remain unchanged when the native backend lands.
- Adding new features requires updating both the contract and the native/JS adapters, making the surface area explicit.
- The selector can emit structured telemetry, enabling us to monitor fallback rates and diagnose runtime issues quickly.
- Documentation of lifecycle expectations reduces ambiguity for follow-on tasks (crypto storage audit, plugin scaffolding, etc.).
