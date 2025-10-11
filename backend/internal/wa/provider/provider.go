package provider

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"time"

	generated "messenger/backend/api/generated"

	"github.com/google/uuid"
)

// Adapter encapsulates calls to mautrix-whatsapp provisioning API.
// For now, this is a placeholder that would call the internal admin API
// authenticated by the configured shared secret.
type Adapter struct {
    BaseURL      string
    SharedSecret string
    HTTPClient   *http.Client
}

func New(baseURL, secret string) *Adapter {
    return &Adapter{
        BaseURL:      baseURL,
        SharedSecret: secret,
        HTTPClient:   &http.Client{Timeout: 10 * time.Second},
    }
}

// Generic proxy helpers for normalized gateway
func (a *Adapter) doGet(ctx context.Context, path string, q url.Values) (*http.Response, error) {
    u, _ := url.Parse(a.BaseURL)
    u.Path = u.Path + path
    if len(q) > 0 { u.RawQuery = q.Encode() }
    req, err := http.NewRequestWithContext(ctx, http.MethodGet, u.String(), nil)
    if err != nil { return nil, err }
    if a.SharedSecret != "" { req.Header.Set("Authorization", "Bearer "+a.SharedSecret) }
    resp, err := a.HTTPClient.Do(req)
    if err != nil { return nil, err }
    if resp.StatusCode/100 != 2 {
        b, _ := io.ReadAll(resp.Body)
        resp.Body.Close()
        return nil, fmt.Errorf("bridge GET %s -> %d: %s", u.Path, resp.StatusCode, string(b))
    }
    return resp, nil
}

func (a *Adapter) doPost(ctx context.Context, path string, q url.Values, body any) (*http.Response, error) {
    u, _ := url.Parse(a.BaseURL)
    u.Path = u.Path + path
    if len(q) > 0 { u.RawQuery = q.Encode() }
    var r *bytes.Reader
    if body != nil { b, _ := json.Marshal(body); r = bytes.NewReader(b) } else { r = bytes.NewReader([]byte("{}")) }
    req, err := http.NewRequestWithContext(ctx, http.MethodPost, u.String(), r)
    if err != nil { return nil, err }
    req.Header.Set("Content-Type", "application/json")
    if a.SharedSecret != "" { req.Header.Set("Authorization", "Bearer "+a.SharedSecret) }
    resp, err := a.HTTPClient.Do(req)
    if err != nil { return nil, err }
    if resp.StatusCode/100 != 2 {
        b, _ := io.ReadAll(resp.Body)
        resp.Body.Close()
        return nil, fmt.Errorf("bridge POST %s -> %d: %s", u.Path, resp.StatusCode, string(b))
    }
    return resp, nil
}

type StartResult struct {
    ConnectionID string
    Method       string // "qr" or "code"
    QRASCII      *string
    Code         *string
    ExpiresAt    time.Time
}

// StartConnection starts a new login via provisioning v3 using shared-secret auth.
// It requests a QR login flow and returns a generic StartResult that higher layers can render.
func (a *Adapter) StartConnection(ctx context.Context, userID uuid.UUID, mxid string) (*StartResult, error) {
    // POST {BaseURL}/_matrix/provision/v3/login/start/qr?user_id=... (Authorization: Bearer <shared_secret>)
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doPost(ctx, "/_matrix/provision/v3/login/start/qr", q, map[string]any{})
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 {
        return nil, fmt.Errorf("bridge start returned %d", resp.StatusCode)
    }
    // Bridge v3 returns a LoginStep. Capture common fields flexibly.
    var raw map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil { return nil, err }
    // Connection/process identifier can be under process_id or login_id depending on build.
    connID := ""
    if v, ok := raw["process_id"].(string); ok { connID = v }
    if connID == "" {
        if v, ok := raw["login_id"].(string); ok { connID = v }
    }
    // Extract QR payload when provided (data or image_url). Prefer raw data string.
    var qr *string
    if v, ok := raw["data"].(string); ok && v != "" { qr = &v }
    // Expiry (best-effort)
    var expiresAt time.Time
    if v, ok := raw["expires_at"].(string); ok && v != "" {
        if t, err := time.Parse(time.RFC3339Nano, v); err == nil { expiresAt = t }
    }
    return &StartResult{ConnectionID: connID, Method: "qr", QRASCII: qr, ExpiresAt: expiresAt}, nil
}

type Status struct {
    State   string // pending|scanned|connected|failed
    Account *struct{
        ExternalID  string
        DisplayName string
    }
    Error *string
}

func (a *Adapter) ConnectionStatus(ctx context.Context, mxid string, connectionID string) (*Status, error) {
    // GET {BaseURL}/_matrix/provision/v3/logins?user_id=...
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doGet(ctx, "/_matrix/provision/v3/logins", q)
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("bridge status %d", resp.StatusCode) }
    var raw map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&raw); err != nil { return nil, err }
    // Shape: { login_ids: ["..."] }
    var st string
    if ids, ok := raw["login_ids"].([]any); ok {
        if len(ids) > 0 {
            st = "connected"
        } else {
            st = "pending"
        }
    } else {
        st = "pending"
    }
    return &Status{State: st}, nil
}

func (a *Adapter) Logout(ctx context.Context, mxid string) error {
    // POST {BaseURL}/_matrix/provision/v3/logout/all?user_id=...
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doPost(ctx, "/_matrix/provision/v3/logout/all", q, nil)
    if err != nil { return err }
    defer resp.Body.Close()
    // consider non-2xx an error, but otherwise ignore body
    if resp.StatusCode/100 != 2 { return fmt.Errorf("bridge logout %d", resp.StatusCode) }
    return nil
}

// New generic methods for normalized gateway
// ListLogins returns the login IDs for the given mxid via provisioning v3.
func (a *Adapter) ListLogins(ctx context.Context, mxid string) ([]string, error) {
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doGet(ctx, "/_matrix/provision/v3/logins", q)
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("logins %d", resp.StatusCode) }
    var out struct { LoginIDs []string `json:"login_ids"` }
    if err := json.NewDecoder(resp.Body).Decode(&out); err != nil { return nil, err }
    return out.LoginIDs, nil
}

func (a *Adapter) getLoginFlows(ctx context.Context, mxid string) (map[string]any, error) {
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doGet(ctx, "/_matrix/provision/v3/login/flows", q)
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("flows %d", resp.StatusCode) }
    var out map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&out); err != nil { return nil, err }
    return out, nil
}

// GetLoginFlows maps the bridge output to a typed response for the API.
func (a *Adapter) GetLoginFlows(ctx context.Context, mxid string) (*generated.BridgeLoginFlowsResponse, error) {
    raw, err := a.getLoginFlows(ctx, mxid)
    if err != nil { return nil, err }
    var flows []generated.BridgeLoginFlow
    if rf, ok := raw["flows"].([]any); ok {
        for _, it := range rf {
            if m, ok := it.(map[string]any); ok {
                id, _ := m["id"].(string)
                name, _ := m["name"].(string)
                desc, _ := m["description"].(string)
                flows = append(flows, generated.BridgeLoginFlow{Id: id, Name: name, Description: desc})
            }
        }
    }
    return &generated.BridgeLoginFlowsResponse{Flows: &flows}, nil
}

// startLoginRaw starts a login flow and returns the raw bridge payload.
func (a *Adapter) startLoginRaw(ctx context.Context, mxid, flow string) (map[string]any, error) {
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doPost(ctx, "/_matrix/provision/v3/login/start/"+flow, q, map[string]any{})
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("start %d", resp.StatusCode) }
    var out map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&out); err != nil { return nil, err }
    return out, nil
}

// StartLoginTyped normalizes the start step to WAStartResponse.
// mapToLoginStep maps a raw step payload to a typed struct.
func mapToLoginStep(out map[string]any) (LoginStep, error) {
    t, _ := out["type"].(string)
    switch t {
    case "display_and_wait":
        var msg, data, img *string
        if m, ok := out["display_and_wait"].(map[string]any); ok {
            if v, ok := m["message"].(string); ok { msg = &v }
            if v, ok := m["data"].(string); ok { data = &v }
            if v, ok := m["image_url"].(string); ok { img = &v }
        }
        return &LoginStepDisplayAndWait{Type: "display_and_wait", DisplayAndWait: &LoginStepDisplayAndWaitDef{Message: msg, Data: data, ImageURL: img}}, nil
    case "user_input":
        var fields []LoginStepUserInputField
        if uin, ok := out["user_input"].(map[string]any); ok {
            if arr, ok := uin["fields"].([]any); ok {
                for _, it := range arr {
                    if m, ok := it.(map[string]any); ok {
                        var f LoginStepUserInputField
                        if v, ok := m["id"].(string); ok { f.ID = &v }
                        if v, ok := m["label"].(string); ok { f.Label = &v }
                        if v, ok := m["kind"].(string); ok { f.Kind = &v }
                        if v, ok := m["secret"].(bool); ok { f.Secret = &v }
                        fields = append(fields, f)
                    }
                }
            }
        }
        return &LoginStepUserInput{Type: "user_input", UserInput: &LoginStepUserInputDef{Fields: fields}}, nil
    case "cookies":
        var names []string
        if ck, ok := out["cookies"].(map[string]any); ok {
            if arr, ok := ck["names"].([]any); ok { for _, it := range arr { if s, ok := it.(string); ok { names = append(names, s) } } }
        }
        return &LoginStepCookies{Type: "cookies", Cookies: &LoginStepCookiesDef{Names: names}}, nil
    case "complete":
        var id *string
        if comp, ok := out["complete"].(map[string]any); ok { if v, ok := comp["user_login_id"].(string); ok { id = &v } }
        return &LoginStepComplete{Type: "complete", Complete: &LoginStepCompleteDef{UserLoginID: id}}, nil
    default:
        // Unknown shape: return a minimal display_and_wait so clients have something to render.
        if m, ok := out["display_and_wait"].(map[string]any); ok {
            var msg, data, img *string
            if v, ok := m["message"].(string); ok { msg = &v }
            if v, ok := m["data"].(string); ok { data = &v }
            if v, ok := m["image_url"].(string); ok { img = &v }
            return &LoginStepDisplayAndWait{Type: "display_and_wait", DisplayAndWait: &LoginStepDisplayAndWaitDef{Message: msg, Data: data, ImageURL: img}}, nil
        }
        return &LoginStepDisplayAndWait{Type: "display_and_wait", DisplayAndWait: &LoginStepDisplayAndWaitDef{}}, nil
    }
}

// StartLoginStep normalizes the first step to the login step union.
func (a *Adapter) StartLoginStep(ctx context.Context, mxid, flow string) (LoginStep, error) {
    out, err := a.startLoginRaw(ctx, mxid, flow)
    if err != nil { return nil, err }
    return mapToLoginStep(out)
}

// submitLoginStepRaw submits a login step and returns the raw bridge payload.
func (a *Adapter) submitLoginStepRaw(ctx context.Context, mxid, processID, stepID, action string, body map[string]any) (map[string]any, error) {
    q := url.Values{}; q.Set("user_id", mxid)
    path := fmt.Sprintf("/_matrix/provision/v3/login/step/%s/%s/%s", processID, stepID, action)
    resp, err := a.doPost(ctx, path, q, body)
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("step %d", resp.StatusCode) }
    var out map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&out); err != nil { return nil, err }
    return out, nil
}

// SubmitLoginStep maps the raw bridge login step into a typed struct suitable for API response.
func (a *Adapter) SubmitLoginStep(ctx context.Context, mxid, processID, stepID, action string, body map[string]any) (LoginStep, error) {
    out, err := a.submitLoginStepRaw(ctx, mxid, processID, stepID, action, body)
    if err != nil { return nil, err }
    return mapToLoginStep(out)
}

func (a *Adapter) WhoamiRaw(ctx context.Context, mxid string) (map[string]any, error) {
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doGet(ctx, "/_matrix/provision/v3/whoami", q)
    if err != nil { return nil, err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return nil, fmt.Errorf("whoami %d", resp.StatusCode) }
    var out map[string]any
    if err := json.NewDecoder(resp.Body).Decode(&out); err != nil { return nil, err }
    return out, nil
}

// Whoami maps the raw whoami to a typed response.
func (a *Adapter) Whoami(ctx context.Context, mxid string) (*generated.BridgeWhoamiResponse, error) {
    out, err := a.WhoamiRaw(ctx, mxid)
    if err != nil { return nil, err }
    var flows []generated.BridgeLoginFlow
    if rawFlows, ok := out["login_flows"].([]any); ok {
        for _, it := range rawFlows {
            if m, ok := it.(map[string]any); ok {
                id, _ := m["id"].(string)
                name, _ := m["name"].(string)
                desc, _ := m["description"].(string)
                flows = append(flows, generated.BridgeLoginFlow{Id: id, Name: name, Description: desc})
            }
        }
    }
    var logins []generated.BridgeWhoamiLogin
    if rawLogins, ok := out["logins"].([]any); ok {
        for _, it := range rawLogins {
            if m, ok := it.(map[string]any); ok {
                id, _ := m["id"].(string)
                name, _ := m["name"].(string)
                var profile *struct{ DisplayName *string `json:"displayName,omitempty"`; ExternalId *string `json:"externalId,omitempty"` }
                if p, ok := m["profile"].(map[string]any); ok {
                    var dn, eid *string
                    if v, ok := p["name"].(string); ok { dn = &v }
                    if v, ok := p["phone"].(string); ok { eid = &v }
                    profile = &struct{ DisplayName *string `json:"displayName,omitempty"`; ExternalId *string `json:"externalId,omitempty"` }{DisplayName: dn, ExternalId: eid}
                }
                var state *string
                if s, ok := m["state"].(map[string]any); ok {
                    if lbl, ok := s["state_event"].(string); ok { state = &lbl }
                }
                logins = append(logins, generated.BridgeWhoamiLogin{Id: id, Name: name, State: state, Profile: profile})
            }
        }
    }
    resp := &generated.BridgeWhoamiResponse{LoginFlows: &flows, Logins: &logins}
    if v, ok := out["homeserver"].(string); ok { resp.Homeserver = &v }
    if v, ok := out["bridge_bot"].(string); ok { resp.BridgeBot = &v }
    if v, ok := out["command_prefix"].(string); ok { resp.CommandPrefix = &v }
    return resp, nil
}

func (a *Adapter) LogoutLogin(ctx context.Context, mxid, loginID string) error {
    q := url.Values{}; q.Set("user_id", mxid)
    resp, err := a.doPost(ctx, "/_matrix/provision/v3/logout/"+loginID, q, nil)
    if err != nil { return err }
    defer resp.Body.Close()
    if resp.StatusCode/100 != 2 { return fmt.Errorf("logout %d", resp.StatusCode) }
    return nil
}
