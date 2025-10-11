package handler

import (
	"context"
	"encoding/json"
	"log"
	"net/http"

	generated "messenger/backend/api/generated"
	brrepo "messenger/backend/internal/bridge/repository"
	userrepo "messenger/backend/internal/user/repository"
	waprovider "messenger/backend/internal/wa/provider"
	middleware "messenger/backend/pkg/middleware"

	"github.com/google/uuid"
)

type WAHandler struct{
    repo      *brrepo.Repo
    provider  *waprovider.Adapter
    waProviderID uuid.UUID
    users userrepo.UserRepository
}

func NewWAHandler(repo *brrepo.Repo, provider *waprovider.Adapter, waProviderID uuid.UUID, users userrepo.UserRepository) *WAHandler {
    return &WAHandler{repo: repo, provider: provider, waProviderID: waProviderID, users: users}
}

func userIDFromCtx(ctx context.Context) (uuid.UUID, bool) {
    v := ctx.Value(middleware.ContextKeyUserID)
    if v == nil { return uuid.UUID{}, false }
    s, ok := v.(string)
    if !ok { return uuid.UUID{}, false }
    id, err := uuid.Parse(s)
    if err != nil { return uuid.UUID{}, false }
    return id, true
}

// getConnections → GetConnections
func (h *WAHandler) GetConnections(w http.ResponseWriter, r *http.Request) {
    w.Header().Set("Content-Type", "application/json")
    uid, ok := userIDFromCtx(r.Context())
    if !ok {
        w.WriteHeader(http.StatusUnauthorized)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"unauthorized"})
        return
    }
    // Resolve user; surface repo errors instead of failing silently
    u, err := h.users.GetUserByID(r.Context(), uid)
    if err != nil {
        log.Printf("[connections] failed to load user id=%s: %v", uid.String(), err)
        w.WriteHeader(http.StatusInternalServerError)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"failed to load user"})
        return
    }
    mxid := ""; if u != nil { mxid = u.MatrixID }
    status := generated.NotConnected
    var account *generated.BridgeAccount
    if mxid != "" {
        if ids, err := h.provider.ListLogins(r.Context(), mxid); err == nil && len(ids) > 0 {
            status = generated.Connected
        }
    }
    // include effective limit for transparency
    maxAcc, err := h.repo.GetEffectiveLimit(r.Context(), uid, &h.waProviderID, "max_accounts", 1)
    if err != nil {
        log.Printf("[connections] failed to read limit: %v", err)
    }
    limits := map[string]any{"max_accounts": maxAcc}
    resp := []generated.BridgeConnection{{
        Provider: "whatsapp",
        Status:   status,
        Account:  account,
        Limits:   &limits,
    }}
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(resp)
}

func (h *WAHandler) BridgeGetLoginFlows(w http.ResponseWriter, r *http.Request, params generated.BridgeGetLoginFlowsParams) {
    w.Header().Set("Content-Type", "application/json")
    // Validate auth and provider
    _, ok := userIDFromCtx(r.Context())
    if !ok { w.WriteHeader(http.StatusUnauthorized); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unauthorized"}); return }
    if params.Provider != "whatsapp" { w.WriteHeader(http.StatusBadRequest); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unsupported provider"}); return }
    // Use current user mxid
    uid, _ := userIDFromCtx(r.Context())
    u, err := h.users.GetUserByID(r.Context(), uid)
    if err != nil { w.WriteHeader(http.StatusInternalServerError); _ = json.NewEncoder(w).Encode(map[string]string{"message":"failed to load user"}); return }
    mxid := ""; if u != nil { mxid = u.MatrixID }
    out, err := h.provider.GetLoginFlows(r.Context(), mxid)
    if err != nil {
        log.Printf("[provision flows] mxid=%s provider=%s error=%v", mxid, params.Provider, err)
        w.WriteHeader(http.StatusBadGateway)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"bridge error"})
        return
    }
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(out)
}

func (h *WAHandler) BridgeStartLogin(w http.ResponseWriter, r *http.Request, flow string, params generated.BridgeStartLoginParams) {
    w.Header().Set("Content-Type", "application/json")
    _, ok := userIDFromCtx(r.Context())
    if !ok { w.WriteHeader(http.StatusUnauthorized); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unauthorized"}); return }
    if params.Provider != "whatsapp" { w.WriteHeader(http.StatusBadRequest); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unsupported provider"}); return }
    // Resolve mxid
    uid, _ := userIDFromCtx(r.Context())
    u, err := h.users.GetUserByID(r.Context(), uid)
    if err != nil { w.WriteHeader(http.StatusInternalServerError); _ = json.NewEncoder(w).Encode(map[string]string{"message":"failed to load user"}); return }
    mxid := ""; if u != nil { mxid = u.MatrixID }
    // Enforce quota: count existing logins from bridge vs effective limit
    limit, err := h.repo.GetEffectiveLimit(r.Context(), uid, &h.waProviderID, "max_accounts", 1)
    if err != nil { log.Printf("[provision start] failed to read limit: %v", err) }
    if mxid != "" {
        if ids, err := h.provider.ListLogins(r.Context(), mxid); err == nil && int64(len(ids)) >= limit {
            w.WriteHeader(http.StatusForbidden)
            _ = json.NewEncoder(w).Encode(map[string]string{"message":"quota exceeded: max_accounts"})
            return
        }
    }
    out, err := h.provider.StartLoginStep(r.Context(), mxid, flow)
    if err != nil {
        log.Printf("[provision start] mxid=%s provider=%s flow=%s error=%v", mxid, params.Provider, flow, err)
        w.WriteHeader(http.StatusBadGateway)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"bridge error"})
        return
    }
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(out)
}

func (h *WAHandler) BridgeSubmitLoginStep(w http.ResponseWriter, r *http.Request, processID string, stepID string, action generated.BridgeSubmitLoginStepParamsAction, params generated.BridgeSubmitLoginStepParams) {
    w.Header().Set("Content-Type", "application/json")
    _, ok := userIDFromCtx(r.Context())
    if !ok { w.WriteHeader(http.StatusUnauthorized); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unauthorized"}); return }
    if params.Provider != "whatsapp" { w.WriteHeader(http.StatusBadRequest); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unsupported provider"}); return }
    var body generated.BridgeSubmitLoginStepJSONBody
    _ = json.NewDecoder(r.Body).Decode(&body)
    // Resolve mxid
    uid, _ := userIDFromCtx(r.Context())
    u, err := h.users.GetUserByID(r.Context(), uid)
    if err != nil { w.WriteHeader(http.StatusInternalServerError); _ = json.NewEncoder(w).Encode(map[string]string{"message":"failed to load user"}); return }
    mxid := ""; if u != nil { mxid = u.MatrixID }
    out, err := h.provider.SubmitLoginStep(r.Context(), mxid, processID, stepID, string(action), map[string]any(body))
    if err != nil {
        log.Printf("[provision step] mxid=%s provider=%s process=%s step=%s action=%s error=%v", mxid, params.Provider, processID, stepID, string(action), err)
        w.WriteHeader(http.StatusBadGateway)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"bridge error"})
        return
    }
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(out)
}

func (h *WAHandler) BridgeWhoami(w http.ResponseWriter, r *http.Request, params generated.BridgeWhoamiParams) {
    w.Header().Set("Content-Type", "application/json")
    _, ok := userIDFromCtx(r.Context())
    if !ok { w.WriteHeader(http.StatusUnauthorized); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unauthorized"}); return }
    if params.Provider != "whatsapp" { w.WriteHeader(http.StatusBadRequest); _ = json.NewEncoder(w).Encode(map[string]string{"message":"unsupported provider"}); return }
    // Resolve mxid
    uid, _ := userIDFromCtx(r.Context())
    u, err := h.users.GetUserByID(r.Context(), uid)
    if err != nil { w.WriteHeader(http.StatusInternalServerError); _ = json.NewEncoder(w).Encode(map[string]string{"message":"failed to load user"}); return }
    mxid := ""; if u != nil { mxid = u.MatrixID }
    out, err := h.provider.Whoami(r.Context(), mxid)
    if err != nil {
        log.Printf("[provision whoami] mxid=%s provider=%s error=%v", mxid, params.Provider, err)
        w.WriteHeader(http.StatusBadGateway)
        _ = json.NewEncoder(w).Encode(map[string]string{"message":"bridge error"})
        return
    }
    w.WriteHeader(http.StatusOK)
    _ = json.NewEncoder(w).Encode(out)
}

func (h *WAHandler) BridgeLogout(w http.ResponseWriter, r *http.Request, loginID string, params generated.BridgeLogoutParams) {
    // Accept either /logout/all or /logout/{id}
    _, ok := userIDFromCtx(r.Context())
    if !ok { w.WriteHeader(http.StatusUnauthorized); return }
    if params.Provider != "whatsapp" { w.WriteHeader(http.StatusBadRequest); return }
    // Resolve mxid
    uid, _ := userIDFromCtx(r.Context())
    u, _ := h.users.GetUserByID(r.Context(), uid)
    mxid := ""; if u != nil { mxid = u.MatrixID }
    if loginID == "all" {
        if err := h.provider.Logout(r.Context(), mxid); err != nil { log.Printf("[provision logout all] mxid=%s provider=%s error=%v", mxid, params.Provider, err) }
    } else {
        if err := h.provider.LogoutLogin(r.Context(), mxid, loginID); err != nil { log.Printf("[provision logout] mxid=%s provider=%s login=%s error=%v", mxid, params.Provider, loginID, err) }
    }
    w.WriteHeader(http.StatusNoContent)
}
