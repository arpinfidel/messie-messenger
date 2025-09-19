package handler

import (
	"bufio"
	"crypto/tls"
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

type emailListRequest struct {
	generated.EmailLoginRequest
	Mailbox     string   `json:"mailbox"`
	SearchFlags []string `json:"searchFlags"`
}

// fetchHeaders is a small helper that signs in to the requested mailbox and
// returns the latest envelopes plus the server-reported unread count. It keeps
// the backend focused on transport and leaves any higher-level logic to the
// client.
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

	const limit uint32 = 25
	seqset := new(imap.SeqSet)

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
		done <- c.Fetch(seqset, []imap.FetchItem{imap.FetchEnvelope, imap.FetchFlags}, messages)
	}()

	headers := make([]generated.EmailMessageHeader, 0, limit)
	for msg := range messages {
		env := msg.Envelope
		if env == nil {
			continue
		}
		var fromPtr *string
		if len(env.From) > 0 {
			addr := env.From[0]
			formatted := fmt.Sprintf("%s@%s", addr.MailboxName, addr.HostName)
			if addr.PersonalName != "" {
				formatted = fmt.Sprintf("%s <%s>", addr.PersonalName, formatted)
			}
			fromPtr = &formatted
		}
		subject := env.Subject
		subjectPtr := &subject
		date := env.Date
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

	h.respondWithHeaders(w, req, "INBOX", nil)
}

// EmailImportant now signals deprecation in favor of /api/v1/email/list.
func (h *EmailHandler) EmailImportant(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "deprecated: use /api/v1/email/list", http.StatusGone)
}

// EmailList handles POST /email/list requests for arbitrary mailbox/flag queries.
func (h *EmailHandler) EmailList(w http.ResponseWriter, r *http.Request) {
	var req emailListRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}

	mailbox := strings.TrimSpace(req.Mailbox)
	if mailbox == "" {
		mailbox = "INBOX"
	}

	h.respondWithHeaders(w, req.EmailLoginRequest, mailbox, req.SearchFlags)
}

// EmailThreads is kept for backwards compatibility with the OpenAPI definition
// but the frontend now threads client-side. Return 410 to signal the move.
func (h *EmailHandler) EmailThreads(w http.ResponseWriter, r *http.Request) {
	http.Error(w, "deprecated: use /api/v1/email/headers for raw headers", http.StatusGone)
}

// EmailHeaders proxies envelopes plus threading identifiers so the client can
// perform grouping locally.
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
	out := make([]generated.EmailRichHeader, 0, 2*perBoxLimit)

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
			var messageIDPtr *string
			if messageID != "" {
				messageIDPtr = &messageID
			}

			inReply := strings.Trim(env.InReplyTo, "<>")
			var inReplyPtr *string
			if inReply != "" {
				inReplyPtr = &inReply
			}

			refs := readRefsFromBody(msg)
			var refsPtr *[]string
			if len(refs) > 0 {
				refsPtr = &refs
			}

			out = append(out, generated.EmailRichHeader{
				From:       fromPtr,
				Subject:    subjPtr,
				Date:       &date,
				MessageId:  messageIDPtr,
				InReplyTo:  inReplyPtr,
				References: refsPtr,
			})
		}
		if err := <-done; err != nil {
			// ignore partial mailbox errors so other boxes can still contribute
		}
	}

	sort.Slice(out, func(i, j int) bool {
		var di, dj time.Time
		if out[i].Date != nil {
			di = *out[i].Date
		}
		if out[j].Date != nil {
			dj = *out[j].Date
		}
		return di.After(dj)
	})

	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(generated.EmailRichHeadersResponse{Messages: out})
}

// readRefsFromBody extracts the References header from any literal body parts
// returned in the IMAP response.
func readRefsFromBody(msg *imap.Message) []string {
	if msg == nil || msg.Body == nil {
		return nil
	}
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
			ids := extractMessageIDs(raw)
			if len(ids) > 0 {
				return ids
			}
		}
	}
	return nil
}

// extractMessageIDs parses a References header and returns the angle-bracketed IDs.
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

func (h *EmailHandler) respondWithHeaders(
	w http.ResponseWriter,
	req generated.EmailLoginRequest,
	mailbox string,
	withFlags []string,
) {
	var criteria *imap.SearchCriteria
	if len(withFlags) > 0 {
		criteria = imap.NewSearchCriteria()
		criteria.WithFlags = append(criteria.WithFlags, withFlags...)
	}

	headers, unread, err := fetchHeaders(req, mailbox, criteria)
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
