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
