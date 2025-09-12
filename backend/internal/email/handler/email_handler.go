package handler

import (
	"crypto/tls"
	"encoding/json"
	"fmt"
	"net/http"

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
func (h *EmailHandler) EmailLoginTest(w http.ResponseWriter, r *http.Request) {
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

	var limit uint32 = 5
	from := uint32(1)
	if mbox.Messages > limit {
		from = mbox.Messages - limit + 1
	}
	seqset := new(imap.SeqSet)
	seqset.AddRange(from, mbox.Messages)

	messages := make(chan *imap.Message, limit)
	done := make(chan error, 1)
	go func() {
		done <- c.Fetch(seqset, []imap.FetchItem{imap.FetchEnvelope}, messages)
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
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	resp := generated.EmailMessagesResponse{Messages: &headers}
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(resp)
}
