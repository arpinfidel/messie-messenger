package handler

import (
    "bufio"
    "crypto/sha1"
    "crypto/tls"
    "encoding/hex"
    "encoding/json"
    "fmt"
    "net/http"
    "net/textproto"
    "sort"
    "strings"
    "time"

    "github.com/emersion/go-imap"
    imapclient "github.com/emersion/go-imap/client"

    "messenger/backend/api/generated"
)

// EmailHandler provides email related endpoints.
type EmailHandler struct{}

// NewEmailHandler creates a new EmailHandler.
func NewEmailHandler() *EmailHandler {
    return &EmailHandler{}
}

// EmailLoginTest handles POST /email/login-test requests.

func fetchHeaders(req generated.EmailLoginRequest, mailbox string, criteria *imap.SearchCriteria) ([]generated.EmailMessageHeader, uint32, error) {
	addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
	c, err := imapclient.DialTLS(addr, &tls.Config{})
	if err != nil {
		return nil, 0, err
	}
	defer c.Logout()

	if err := c.Login(string(req.Email), req.AppPassword); err != nil {
		return nil, 0, fmt.Errorf("authentication failed")
	}

	mbox, err := c.Select(mailbox, true)
	if err != nil {
		return nil, 0, err
	}

	seqset := new(imap.SeqSet)
	var limit uint32 = 5

	if criteria != nil {
		ids, err := c.Search(criteria)
		if err != nil {
			return nil, 0, err
		}
		if len(ids) == 0 {
			return []generated.EmailMessageHeader{}, mbox.Unseen, nil
		}
		start := 0
		if len(ids) > int(limit) {
			start = len(ids) - int(limit)
		}
		for _, id := range ids[start:] {
			seqset.AddNum(id)
		}
	} else {
		from := uint32(1)
		if mbox.Messages > limit {
			from = mbox.Messages - limit + 1
		}
		seqset.AddRange(from, mbox.Messages)
	}

    messages := make(chan *imap.Message, limit)
    done := make(chan error, 1)
    go func() {
        // Fetch envelope + flags so we can derive unread counts higher up if needed later
        done <- c.Fetch(seqset, []imap.FetchItem{imap.FetchEnvelope, imap.FetchFlags}, messages)
    }()

	headers := make([]generated.EmailMessageHeader, 0, limit)
	for msg := range messages {
		var fromPtr *string
		if len(msg.Envelope.From) > 0 {
			addr := msg.Envelope.From[0]
			formatted := fmt.Sprintf("%s@%s", addr.MailboxName, addr.HostName)
			if addr.PersonalName != "" {
				formatted = fmt.Sprintf("%s <%s>", addr.PersonalName, formatted)
			}
			fromPtr = &formatted
		}
		subject := msg.Envelope.Subject
		subjectPtr := &subject
		date := msg.Envelope.Date
		headers = append(headers, generated.EmailMessageHeader{
			From:    fromPtr,
			Subject: subjectPtr,
			Date:    &date,
		})
	}
	if err := <-done; err != nil {
		return nil, 0, err
	}

    return headers, mbox.Unseen, nil
}

// computeThreadBaseID tries to find a stable root identifier for a thread using
// In-Reply-To if available, otherwise falls back to Message-ID. The returned
// value is the raw message id without surrounding brackets.
func computeThreadBaseID(env *imap.Envelope) string {
    // Use In-Reply-To (parent) if present
    if env.InReplyTo != "" {
        id := strings.TrimSpace(env.InReplyTo)
        id = strings.TrimPrefix(id, "<")
        id = strings.TrimSuffix(id, ">")
        if id != "" {
            return id
        }
    }
    // Fallback to this message's Message-ID
    id := strings.TrimSpace(env.MessageId)
    id = strings.TrimPrefix(id, "<")
    id = strings.TrimSuffix(id, ">")
    return id
}

// computeThreadKey returns a stable hex-encoded SHA1 of the base id.
func computeThreadKey(env *imap.Envelope) string {
    base := computeThreadBaseID(env)
    h := sha1.Sum([]byte(base))
    return hex.EncodeToString(h[:])
}

// threadPreview represents a thread row for the thread list endpoint.
type threadPreview struct {
    ThreadKey     string     `json:"threadKey"`
    LatestSubject string     `json:"latestSubject"`
    From          *string    `json:"from,omitempty"`
    Date          *time.Time `json:"date,omitempty"`
    UnreadCount   int32      `json:"unreadCount"`
    Count         int        `json:"count"`
    HasReply      bool       `json:"hasReply"`
}

// threadListResponse is returned by /email/threads
type threadListResponse struct {
    Threads   []threadPreview `json:"threads"`
    NextCursor *int64         `json:"cursor,omitempty"`
}

// rich header payload for proxying threading to client
type richHeader struct {
    From       *string    `json:"from,omitempty"`
    Subject    *string    `json:"subject,omitempty"`
    Date       *time.Time `json:"date,omitempty"`
    MessageID  string     `json:"messageId"`
    InReplyTo  string     `json:"inReplyTo,omitempty"`
    References []string   `json:"references,omitempty"`
}

type richHeadersResponse struct {
    Messages []richHeader `json:"messages"`
}

// EmailLoginTest handles POST /email/login-test requests.
func (h *EmailHandler) EmailLoginTest(w http.ResponseWriter, r *http.Request) {
	var req generated.EmailLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	headers, unread, err := fetchHeaders(req, "INBOX", nil)
	if err != nil {
		status := http.StatusInternalServerError
		if err.Error() == "authentication failed" {
			status = http.StatusUnauthorized
		}
		http.Error(w, err.Error(), status)
		return
	}

	unreadCount := int32(unread)
	resp := generated.EmailMessagesResponse{Messages: &headers, UnreadCount: &unreadCount}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// EmailInbox handles POST /email/inbox requests.
func (h *EmailHandler) EmailInbox(w http.ResponseWriter, r *http.Request) {
	var req generated.EmailLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	headers, unread, err := fetchHeaders(req, "INBOX", nil)
	if err != nil {
		status := http.StatusInternalServerError
		if err.Error() == "authentication failed" {
			status = http.StatusUnauthorized
		}
		http.Error(w, err.Error(), status)
		return
	}

	unreadCount := int32(unread)
	resp := generated.EmailMessagesResponse{Messages: &headers, UnreadCount: &unreadCount}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// EmailImportant handles POST /email/important requests.
func (h *EmailHandler) EmailImportant(w http.ResponseWriter, r *http.Request) {
	var req generated.EmailLoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	criteria := imap.NewSearchCriteria()
	criteria.WithFlags = []string{imap.FlaggedFlag}

	headers, unread, err := fetchHeaders(req, "INBOX", criteria)
	if err != nil {
		status := http.StatusInternalServerError
		if err.Error() == "authentication failed" {
			status = http.StatusUnauthorized
		}
		http.Error(w, err.Error(), status)
		return
	}

	unreadCount := int32(unread)
	resp := generated.EmailMessagesResponse{Messages: &headers, UnreadCount: &unreadCount}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}

// EmailThreads handles POST /email/threads requests.
func (h *EmailHandler) EmailThreads(w http.ResponseWriter, r *http.Request) {
    var req generated.EmailLoginRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    // Optional cursor as unix timestamp for pagination (older than this date)
    var before *time.Time
    if cursorStr := r.URL.Query().Get("cursor"); cursorStr != "" {
        if ts, err := parseInt64(cursorStr); err == nil {
            t := time.Unix(ts, 0)
            before = &t
        }
    }

    // Connect to IMAP
    addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
    c, err := imapclient.DialTLS(addr, &tls.Config{})
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer c.Logout()

    if err := c.Login(string(req.Email), req.AppPassword); err != nil {
        http.Error(w, "authentication failed", http.StatusUnauthorized)
        return
    }

    mbox, err := c.Select("INBOX", true)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    // Build sequence set: fetch latest N or those before the cursor date
    const limit uint32 = 100
    seqset := new(imap.SeqSet)
    if before != nil {
        criteria := imap.NewSearchCriteria()
        criteria.SentBefore = *before
        ids, err := c.Search(criteria)
        if err != nil || len(ids) == 0 {
            w.Header().Set("Content-Type", "application/json")
            _ = json.NewEncoder(w).Encode(threadListResponse{Threads: []threadPreview{}})
            return
        }
        start := 0
        if len(ids) > int(limit) {
            start = len(ids) - int(limit)
        }
        for _, id := range ids[start:] {
            seqset.AddNum(id)
        }
    } else {
        from := uint32(1)
        if mbox.Messages > limit {
            from = mbox.Messages - limit + 1
        }
        seqset.AddRange(from, mbox.Messages)
    }

    // Fetch Envelope + Flags
    messages := make(chan *imap.Message, limit)
    done := make(chan error, 1)
    go func() {
        done <- c.Fetch(seqset, []imap.FetchItem{imap.FetchEnvelope, imap.FetchFlags}, messages)
    }()

    // Group by threadKey
    type acc struct {
        latest   *imap.Envelope
        from     *string
        unread   int32
        count    int
        hasReply bool
    }
    byThread := map[string]*acc{}
    var oldest time.Time
    first := true

    for msg := range messages {
        env := msg.Envelope
        if env == nil {
            continue
        }
        // Track oldest message date for cursor
        if first {
            oldest = env.Date
            first = false
        } else if env.Date.Before(oldest) {
            oldest = env.Date
        }

        key := computeThreadKey(env)
        // build formatted from
        var fromPtr *string
        if len(env.From) > 0 {
            a := env.From[0]
            formatted := fmt.Sprintf("%s@%s", a.MailboxName, a.HostName)
            if a.PersonalName != "" {
                formatted = fmt.Sprintf("%s <%s>", a.PersonalName, formatted)
            }
            fromPtr = &formatted
        }
        // unread?
        isUnread := true
        for _, f := range msg.Flags {
            if f == imap.SeenFlag {
                isUnread = false
                break
            }
        }

        a := byThread[key]
        if a == nil {
            a = &acc{latest: env, from: fromPtr, unread: 0}
            byThread[key] = a
        }
        a.count++
        if strings.TrimSpace(env.InReplyTo) != "" {
            a.hasReply = true
        }
        // Update latest by date
        if a.latest == nil || env.Date.After(a.latest.Date) {
            a.latest = env
            a.from = fromPtr
        }
        if isUnread {
            a.unread++
        }
    }
    if err := <-done; err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    // Build previews
    previews := make([]threadPreview, 0, len(byThread))
    for key, a := range byThread {
        // Only include real threads (emails and their replies). Hide single-message roots.
        if a.count < 2 && !a.hasReply {
            continue
        }
        subject := ""
        if a.latest != nil {
            subject = a.latest.Subject
        }
        var datePtr *time.Time
        if a.latest != nil {
            d := a.latest.Date
            datePtr = &d
        }
        previews = append(previews, threadPreview{
            ThreadKey:     key,
            LatestSubject: subject,
            From:          a.from,
            Date:          datePtr,
            UnreadCount:   a.unread,
            Count:         a.count,
            HasReply:      a.hasReply,
        })
    }
    // Sort by date desc
    sort.Slice(previews, func(i, j int) bool {
        di := time.Time{}
        dj := time.Time{}
        if previews[i].Date != nil {
            di = *previews[i].Date
        }
        if previews[j].Date != nil {
            dj = *previews[j].Date
        }
        return di.After(dj)
    })

    var cursor *int64
    if !first {
        ts := oldest.Unix()
        cursor = &ts
    }

    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(threadListResponse{Threads: previews, NextCursor: cursor})
}

// EmailThreadMessages handles POST /email/thread/{threadKey}/messages
// Returns the headers for all recent messages belonging to a specific thread key.
func (h *EmailHandler) EmailThreadMessages(w http.ResponseWriter, r *http.Request) {
    // Extract threadKey from URL path (suffix after last '/')
    path := r.URL.Path
    idx := strings.LastIndex(path, "/")
    if idx < 0 || idx == len(path)-1 {
        http.Error(w, "missing threadKey", http.StatusBadRequest)
        return
    }
    threadKey := path[idx+1:]

    var req generated.EmailLoginRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
    c, err := imapclient.DialTLS(addr, &tls.Config{})
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer c.Logout()

    if err := c.Login(string(req.Email), req.AppPassword); err != nil {
        http.Error(w, "authentication failed", http.StatusUnauthorized)
        return
    }

    mbox, err := c.Select("INBOX", true)
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    // Fetch a larger window to capture the thread members
    const limit uint32 = 200
    seqset := new(imap.SeqSet)
    from := uint32(1)
    if mbox.Messages > limit {
        from = mbox.Messages - limit + 1
    }
    seqset.AddRange(from, mbox.Messages)

    messages := make(chan *imap.Message, limit)
    done := make(chan error, 1)
    go func() {
        done <- c.Fetch(seqset, []imap.FetchItem{imap.FetchEnvelope, imap.FetchFlags}, messages)
    }()

    headers := make([]generated.EmailMessageHeader, 0, 16)
    var unreadCount int32

    for msg := range messages {
        env := msg.Envelope
        if env == nil {
            continue
        }
        key := computeThreadKey(env)
        if key != threadKey {
            continue
        }
        // from
        var fromPtr *string
        if len(env.From) > 0 {
            a := env.From[0]
            formatted := fmt.Sprintf("%s@%s", a.MailboxName, a.HostName)
            if a.PersonalName != "" {
                formatted = fmt.Sprintf("%s <%s>", a.PersonalName, formatted)
            }
            fromPtr = &formatted
        }
        subj := env.Subject
        subjPtr := &subj
        date := env.Date
        // unread?
        isUnread := true
        for _, f := range msg.Flags {
            if f == imap.SeenFlag {
                isUnread = false
                break
            }
        }
        if isUnread {
            unreadCount++
        }
        headers = append(headers, generated.EmailMessageHeader{From: fromPtr, Subject: subjPtr, Date: &date})
    }
    if err := <-done; err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }

    // Sort ascending by date
    sort.Slice(headers, func(i, j int) bool {
        di := time.Time{}
        dj := time.Time{}
        if headers[i].Date != nil {
            di = *headers[i].Date
        }
        if headers[j].Date != nil {
            dj = *headers[j].Date
        }
        return di.Before(dj)
    })

    resp := generated.EmailMessagesResponse{Messages: &headers, UnreadCount: &unreadCount}
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(resp)
}

// Helper to parse int64 safely
func parseInt64(s string) (int64, error) {
    var n int64
    _, err := fmt.Sscan(s, &n)
    return n, err
}

// Thread fetch by base Message-ID across common mailboxes.
type threadByBaseRequest struct {
    generated.EmailLoginRequest
    BaseId string `json:"baseId"`
}

// EmailThreadByBase handles POST /email/thread/messages
// Body: { host, port, email, appPassword, baseId }
// Returns all headers in the thread (Message-ID == baseId OR In-Reply-To == baseId OR References contains baseId)
func (h *EmailHandler) EmailThreadByBase(w http.ResponseWriter, r *http.Request) {
    var req threadByBaseRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }
    base := strings.Trim(req.BaseId, "<>")
    if base == "" {
        http.Error(w, "missing baseId", http.StatusBadRequest)
        return
    }

    addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
    c, err := imapclient.DialTLS(addr, &tls.Config{})
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer c.Logout()

    if err := c.Login(string(req.Email), req.AppPassword); err != nil {
        http.Error(w, "authentication failed", http.StatusUnauthorized)
        return
    }

    mailboxes := []string{"INBOX", "[Gmail]/All Mail", "[Gmail]/Sent Mail", "Sent", "Sent Items"}
    const perBoxLimit uint32 = 2000
    headers := make([]generated.EmailMessageHeader, 0, 64)
    var unreadCount int32

    for _, mboxName := range mailboxes {
        mbox, err := c.Select(mboxName, true)
        if err != nil {
            continue // ignore missing mailboxes
        }
        seqset := new(imap.SeqSet)
        from := uint32(1)
        if mbox.Messages > perBoxLimit {
            from = mbox.Messages - perBoxLimit + 1
        }
        seqset.AddRange(from, mbox.Messages)

        // Fetch envelope + flags + targeted header fields using raw fetch item
        fetchItems := []imap.FetchItem{imap.FetchEnvelope, imap.FetchFlags, imap.FetchItem("BODY.PEEK[HEADER.FIELDS (Message-ID In-Reply-To References)]")}
        messages := make(chan *imap.Message, 100)
        done := make(chan error, 1)
        go func() { done <- c.Fetch(seqset, fetchItems, messages) }()

        for msg := range messages {
            env := msg.Envelope
            if env == nil {
                continue
            }
            mid := strings.Trim(env.MessageId, "<>")
            irt := strings.Trim(env.InReplyTo, "<>")
            refs := readRefsFromBody(msg)
            // Thread membership condition
            inThread := mid == base || irt == base
            if !inThread {
                for _, r := range refs {
                    if r == base { inThread = true; break }
                }
            }
            if !inThread { continue }

            // from
            var fromPtr *string
            if len(env.From) > 0 {
                a := env.From[0]
                formatted := fmt.Sprintf("%s@%s", a.MailboxName, a.HostName)
                if a.PersonalName != "" { formatted = fmt.Sprintf("%s <%s>", a.PersonalName, formatted) }
                fromPtr = &formatted
            }
            subj := env.Subject
            subjPtr := &subj
            date := env.Date
            // unread?
            isUnread := true
            for _, f := range msg.Flags { if f == imap.SeenFlag { isUnread = false; break } }
            if isUnread { unreadCount++ }
            headers = append(headers, generated.EmailMessageHeader{From: fromPtr, Subject: subjPtr, Date: &date})
        }
        if err := <-done; err != nil { /* ignore partial errors */ }
    }

    // Sort by date asc
    sort.Slice(headers, func(i, j int) bool {
        di := time.Time{}; dj := time.Time{}
        if headers[i].Date != nil { di = *headers[i].Date }
        if headers[j].Date != nil { dj = *headers[j].Date }
        return di.Before(dj)
    })

    resp := generated.EmailMessagesResponse{Messages: &headers, UnreadCount: &unreadCount}
    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(resp)
}

// readRefsFromBody reads References header value from BODY[...] part in msg.Body
func readRefsFromBody(msg *imap.Message) []string {
    if msg == nil || msg.Body == nil {
        return nil
    }
    // Iterate over all literal bodies and try to parse MIME headers.
    // We don't rely on the map key type (it can be *BodySectionName).
    for _, lit := range msg.Body {
        if lit == nil {
            continue
        }
        tp := textproto.NewReader(bufio.NewReader(lit))
        hdr, err := tp.ReadMIMEHeader()
        if err != nil {
            continue
        }
        if raw := hdr.Get("References"); raw != "" {
            if ids := extractMessageIDs(raw); len(ids) > 0 {
                return ids
            }
        }
    }
    return nil
}

// EmailHeaders is a proxy endpoint that returns latest message headers including
// Message-ID/In-Reply-To/References for client-side threading.
func (h *EmailHandler) EmailHeaders(w http.ResponseWriter, r *http.Request) {
    var req generated.EmailLoginRequest
    if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
        http.Error(w, err.Error(), http.StatusBadRequest)
        return
    }

    addr := fmt.Sprintf("%s:%d", req.Host, req.Port)
    c, err := imapclient.DialTLS(addr, &tls.Config{})
    if err != nil {
        http.Error(w, err.Error(), http.StatusInternalServerError)
        return
    }
    defer c.Logout()

    if err := c.Login(string(req.Email), req.AppPassword); err != nil {
        http.Error(w, "authentication failed", http.StatusUnauthorized)
        return
    }

    mailboxes := []string{"INBOX", "[Gmail]/All Mail", "[Gmail]/Sent Mail", "Sent", "Sent Items"}
    const perBoxLimit uint32 = 1000
    out := make([]richHeader, 0, 2*perBoxLimit)

    for _, mboxName := range mailboxes {
        mbox, err := c.Select(mboxName, true)
        if err != nil {
            continue
        }
        seqset := new(imap.SeqSet)
        from := uint32(1)
        if mbox.Messages > perBoxLimit {
            from = mbox.Messages - perBoxLimit + 1
        }
        seqset.AddRange(from, mbox.Messages)

        fetchItems := []imap.FetchItem{imap.FetchEnvelope, imap.FetchItem("BODY.PEEK[HEADER.FIELDS (Message-ID In-Reply-To References)]")}
        messages := make(chan *imap.Message, 200)
        done := make(chan error, 1)
        go func() { done <- c.Fetch(seqset, fetchItems, messages) }()

        for msg := range messages {
            env := msg.Envelope
            if env == nil {
                continue
            }
            var fromPtr *string
            if len(env.From) > 0 {
                a := env.From[0]
                formatted := fmt.Sprintf("%s@%s", a.MailboxName, a.HostName)
                if a.PersonalName != "" {
                    formatted = fmt.Sprintf("%s <%s>", a.PersonalName, formatted)
                }
                fromPtr = &formatted
            }
            subj := env.Subject
            subjPtr := &subj
            date := env.Date

            messageID := strings.Trim(env.MessageId, "<>")
            inReply := strings.Trim(env.InReplyTo, "<>")
            refs := readRefsFromBody(msg)

            out = append(out, richHeader{
                From:       fromPtr,
                Subject:    subjPtr,
                Date:       &date,
                MessageID:  messageID,
                InReplyTo:  inReply,
                References: refs,
            })
        }
        if err := <-done; err != nil {
            // ignore partial mailbox errors
        }
    }

    // Sort descending by date so UI can take latest easily
    sort.Slice(out, func(i, j int) bool {
        di := time.Time{}
        dj := time.Time{}
        if out[i].Date != nil { di = *out[i].Date }
        if out[j].Date != nil { dj = *out[j].Date }
        return di.After(dj)
    })

    w.Header().Set("Content-Type", "application/json")
    _ = json.NewEncoder(w).Encode(richHeadersResponse{Messages: out})
}

// readReferences reads and splits References header into individual ids
func readReferences(msg *imap.Message, section *imap.BodySectionName) []string {
    r := msg.GetBody(section)
    if r == nil {
        return nil
    }
    tp := textproto.NewReader(bufio.NewReader(r))
    hdr, err := tp.ReadMIMEHeader()
    if err != nil {
        return nil
    }
    raw := hdr.Get("References")
    if raw == "" {
        return nil
    }
    return extractMessageIDs(raw)
}

// extractMessageIDs parses a header value and returns ids contained in angle brackets
func extractMessageIDs(s string) []string {
    var ids []string
    start := -1
    for i := 0; i < len(s); i++ {
        switch s[i] {
        case '<':
            start = i + 1
        case '>':
            if start >= 0 {
                id := strings.TrimSpace(s[start:i])
                if id != "" {
                    ids = append(ids, id)
                }
                start = -1
            }
        }
    }
    return ids
}
