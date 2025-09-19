package main

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/joho/godotenv"
	"gopkg.in/yaml.v3"
)

const (
	defaultIssueTypeValue = "Task"
	defaultYAMLFile       = "jira-tasks.yaml"
	defaultMaxResults     = 50
	jiraAPIPrefix         = "/rest/api/3"
)

func main() {
	ctx := context.Background()
	if err := run(ctx); err != nil {
		fmt.Fprintf(os.Stderr, "Error: %v\n", err)
		os.Exit(1)
	}
}

func run(ctx context.Context) error {
	if len(os.Args) < 2 {
		printUsage()
		return errors.New("missing command")
	}

	command := os.Args[1]

	if command == "help" || command == "--help" || command == "-h" {
		printUsage()
		return nil
	}

	if err := maybeLoadDotEnv(); err != nil {
		return err
	}

	cfg, err := loadConfig()
	if err != nil {
		return err
	}

	client := newJiraClient(cfg)

	switch command {
	case "pull":
		return runPull(ctx, client, cfg)
	case "push":
		if err := runPush(ctx, client, cfg); err != nil {
			return err
		}
		fmt.Println("Refreshing local YAML from Jira...")
		return runPull(ctx, client, cfg)
	default:
		printUsage()
		return fmt.Errorf("unknown command: %s", command)
	}
}

func printUsage() {
	fmt.Println("Usage: go run ./backend/cmd/jira-sync <pull|push>")
	fmt.Println()
	fmt.Println("Commands:")
	fmt.Println("  pull   Fetch issues from Jira and write them to the YAML file")
	fmt.Println("  push   Read the YAML file and update/create issues in Jira")
}

type config struct {
	BaseURL          string
	Email            string
	APIToken         string
	ProjectKey       string
	DefaultIssueType string
	JQL              string
	YAMLPath         string
	MaxResults       int
}

func maybeLoadDotEnv() error {
	candidates := []string{".env", "../.env"}
	for _, path := range candidates {
		if _, err := os.Stat(path); err == nil {
			if err := godotenv.Overload(path); err != nil {
				return fmt.Errorf("load %s: %w", path, err)
			}
		}
	}
	return nil
}

func loadConfig() (config, error) {
	baseURL := strings.TrimSpace(os.Getenv("JIRA_BASE_URL"))
	if baseURL == "" {
		return config{}, errors.New("JIRA_BASE_URL is required")
	}
	baseURL = strings.TrimSuffix(baseURL, "/")
	if _, err := url.ParseRequestURI(baseURL); err != nil {
		return config{}, fmt.Errorf("invalid JIRA_BASE_URL: %w", err)
	}

	email := strings.TrimSpace(os.Getenv("JIRA_EMAIL"))
	if email == "" {
		return config{}, errors.New("JIRA_EMAIL is required")
	}

	token := strings.TrimSpace(os.Getenv("JIRA_API_TOKEN"))
	if token == "" {
		return config{}, errors.New("JIRA_API_TOKEN is required")
	}

	projectKey := strings.TrimSpace(os.Getenv("JIRA_PROJECT_KEY"))
	if projectKey == "" {
		return config{}, errors.New("JIRA_PROJECT_KEY is required")
	}

	defaultIssueType := strings.TrimSpace(os.Getenv("JIRA_DEFAULT_ISSUE_TYPE"))
	if defaultIssueType == "" {
		defaultIssueType = defaultIssueTypeValue
	}

	jql := strings.TrimSpace(os.Getenv("JIRA_JQL"))
	if jql == "" {
		jql = fmt.Sprintf("project = %s ORDER BY created DESC", projectKey)
	}

	yamlPath := strings.TrimSpace(os.Getenv("JIRA_YAML_PATH"))
	if yamlPath == "" {
		yamlPath = defaultYAMLFile
	}
	yamlPath, err := resolveYAMLPath(yamlPath)
	if err != nil {
		return config{}, err
	}

	maxResults := defaultMaxResults
	if raw := strings.TrimSpace(os.Getenv("JIRA_MAX_RESULTS")); raw != "" {
		parsed, err := strconv.Atoi(raw)
		if err != nil || parsed <= 0 {
			return config{}, fmt.Errorf("invalid JIRA_MAX_RESULTS: %s", raw)
		}
		maxResults = parsed
	}

	return config{
		BaseURL:          baseURL,
		Email:            email,
		APIToken:         token,
		ProjectKey:       projectKey,
		DefaultIssueType: defaultIssueType,
		JQL:              jql,
		YAMLPath:         yamlPath,
		MaxResults:       maxResults,
	}, nil
}

func resolveYAMLPath(path string) (string, error) {
	if path == "" {
		return "", errors.New("yaml path cannot be empty")
	}

	clean := filepath.Clean(path)
	if filepath.IsAbs(clean) {
		return clean, nil
	}

	repoRoot, err := findRepoRoot()
	if err != nil {
		wd, wdErr := os.Getwd()
		if wdErr != nil {
			return "", fmt.Errorf("determine working directory: %w", wdErr)
		}
		return filepath.Join(wd, clean), nil
	}

	return filepath.Join(repoRoot, clean), nil
}

func findRepoRoot() (string, error) {
	wd, err := os.Getwd()
	if err != nil {
		return "", fmt.Errorf("determine working directory: %w", err)
	}

	for {
		candidate := filepath.Join(wd, ".git")
		if info, err := os.Stat(candidate); err == nil && info.IsDir() {
			return wd, nil
		}

		parent := filepath.Dir(wd)
		if parent == wd {
			return "", errors.New("unable to locate repository root (.git directory not found)")
		}
		wd = parent
	}
}

type jiraClient struct {
	httpClient     *http.Client
	baseURL        string
	authHeader     string
	issueTypeMu    sync.Mutex
	issueTypeCache map[string]string
}

func newJiraClient(cfg config) *jiraClient {
	credentials := base64.StdEncoding.EncodeToString([]byte(cfg.Email + ":" + cfg.APIToken))
	return &jiraClient{
		httpClient: &http.Client{Timeout: 30 * time.Second},
		baseURL:    cfg.BaseURL,
		authHeader: "Basic " + credentials,
	}
}

func (c *jiraClient) newRequest(ctx context.Context, method, path string, query url.Values, body interface{}) (*http.Request, error) {
	var buf io.ReadWriter
	if body != nil {
		buf = &bytes.Buffer{}
		if err := json.NewEncoder(buf).Encode(body); err != nil {
			return nil, fmt.Errorf("encode request body: %w", err)
		}
	}
	endpoint := c.baseURL + path
	if query != nil {
		if strings.Contains(endpoint, "?") {
			endpoint += "&" + query.Encode()
		} else {
			endpoint += "?" + query.Encode()
		}
	}
	req, err := http.NewRequestWithContext(ctx, method, endpoint, buf)
	if err != nil {
		return nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", c.authHeader)
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	return req, nil
}

func (c *jiraClient) do(req *http.Request, v interface{}) error {
	resp, err := c.httpClient.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode >= http.StatusBadRequest {
		b, _ := io.ReadAll(resp.Body)
		msg := strings.TrimSpace(string(b))
		if msg == "" {
			msg = resp.Status
		}
		return fmt.Errorf("jira API error: %s", msg)
	}

	if v == nil {
		io.Copy(io.Discard, resp.Body)
		return nil
	}

	return json.NewDecoder(resp.Body).Decode(v)
}

func (c *jiraClient) searchIssues(ctx context.Context, jql string, startAt, maxResults int) (jiraSearchResponse, error) {
	query := url.Values{}
	query.Set("jql", jql)
	query.Set("startAt", strconv.Itoa(startAt))
	query.Set("maxResults", strconv.Itoa(maxResults))
	query.Set("fields", "summary,description,labels,issuetype,status,assignee,priority,parent")

	req, err := c.newRequest(ctx, http.MethodGet, jiraAPIPrefix+"/search", query, nil)
	if err != nil {
		return jiraSearchResponse{}, err
	}

	var payload jiraSearchResponse
	if err := c.do(req, &payload); err != nil {
		return jiraSearchResponse{}, err
	}
	return payload, nil
}

func (c *jiraClient) updateIssue(ctx context.Context, key string, fields map[string]interface{}) error {
	body := map[string]interface{}{"fields": fields}
	req, err := c.newRequest(ctx, http.MethodPut, jiraAPIPrefix+"/issue/"+key, nil, body)
	if err != nil {
		return err
	}
	return c.do(req, nil)
}

func (c *jiraClient) createIssue(ctx context.Context, fields map[string]interface{}) (string, error) {
	body := map[string]interface{}{"fields": fields}
	req, err := c.newRequest(ctx, http.MethodPost, jiraAPIPrefix+"/issue", nil, body)
	if err != nil {
		return "", err
	}
	var resp struct {
		Key string `json:"key"`
	}
	if err := c.do(req, &resp); err != nil {
		return "", err
	}
	if resp.Key == "" {
		return "", errors.New("jira did not return an issue key")
	}
	return resp.Key, nil
}

type jiraSearchResponse struct {
	StartAt    int         `json:"startAt"`
	MaxResults int         `json:"maxResults"`
	Total      int         `json:"total"`
	Issues     []jiraIssue `json:"issues"`
}

type jiraIssue struct {
	Key    string     `json:"key"`
	Fields jiraFields `json:"fields"`
}

type jiraFields struct {
	Summary     string          `json:"summary"`
	Description json.RawMessage `json:"description"`
	Labels      []string        `json:"labels"`
	IssueType   struct {
		Name string `json:"name"`
	} `json:"issuetype"`
	Status struct {
		Name string `json:"name"`
	} `json:"status"`
	Assignee *struct {
		AccountID   string `json:"accountId"`
		DisplayName string `json:"displayName"`
	} `json:"assignee"`
	Priority *struct {
		Name string `json:"name"`
	} `json:"priority"`
	Parent *struct {
		Key string `json:"key"`
	} `json:"parent"`
}

type issueRecord struct {
	Key                 string   `yaml:"key,omitempty"`
	Summary             string   `yaml:"summary"`
	Description         string   `yaml:"description,omitempty"`
	Labels              []string `yaml:"labels,omitempty"`
	IssueType           string   `yaml:"issueType,omitempty"`
	ForceIssueType      bool     `yaml:"forceIssueType,omitempty"`
	Status              string   `yaml:"status,omitempty"`
	Priority            string   `yaml:"priority,omitempty"`
	ParentKey           string   `yaml:"parent,omitempty"`
	AssigneeAccountID   string   `yaml:"assigneeAccountId,omitempty"`
	AssigneeDisplayName string   `yaml:"assigneeDisplayName,omitempty"`
	Delete              bool     `yaml:"delete,omitempty"`
}

type issueFile struct {
	Issues []issueRecord `yaml:"issues"`
}

func runPull(ctx context.Context, client *jiraClient, cfg config) error {
	fmt.Println("Fetching issues from Jira...")
	var allIssues []jiraIssue
	startAt := 0
	for {
		resp, err := client.searchIssues(ctx, cfg.JQL, startAt, cfg.MaxResults)
		if err != nil {
			return fmt.Errorf("search issues: %w", err)
		}
		allIssues = append(allIssues, resp.Issues...)
		startAt += len(resp.Issues)
		if startAt >= resp.Total || len(resp.Issues) == 0 {
			break
		}
	}

	records := make([]issueRecord, 0, len(allIssues))
	for _, issue := range allIssues {
		description, err := adfToPlainText(issue.Fields.Description)
		if err != nil {
			return fmt.Errorf("parse description for %s: %w", issue.Key, err)
		}
		record := issueRecord{
			Key:         issue.Key,
			Summary:     issue.Fields.Summary,
			Description: description,
			Labels:      append([]string(nil), issue.Fields.Labels...),
			IssueType:   issue.Fields.IssueType.Name,
			Status:      issue.Fields.Status.Name,
		}
		if issue.Fields.Priority != nil {
			record.Priority = issue.Fields.Priority.Name
		}
		if issue.Fields.Parent != nil {
			record.ParentKey = issue.Fields.Parent.Key
		}
		if issue.Fields.Assignee != nil {
			record.AssigneeAccountID = issue.Fields.Assignee.AccountID
			record.AssigneeDisplayName = issue.Fields.Assignee.DisplayName
		}
		records = append(records, record)
	}

	fileData := issueFile{Issues: records}
	if fileData.Issues == nil {
		fileData.Issues = []issueRecord{}
	}

	if err := writeIssueFile(cfg.YAMLPath, fileData); err != nil {
		return err
	}

	fmt.Printf("Wrote %d issue(s) to %s\n", len(records), cfg.YAMLPath)
	return nil
}

func runPush(ctx context.Context, client *jiraClient, cfg config) error {
	data, err := readIssueFile(cfg.YAMLPath)
	if err != nil {
		return err
	}
	if len(data.Issues) == 0 {
		fmt.Println("No issues found in YAML file; nothing to push.")
		return nil
	}

	var remaining []issueRecord
	for _, issue := range data.Issues {
		if issue.Delete {
			key := strings.TrimSpace(issue.Key)
			if key == "" {
				fmt.Println("Skipping delete flag on issue without a key.")
				remaining = append(remaining, issue)
				continue
			}
			if err := client.deleteIssue(ctx, key); err != nil {
				return fmt.Errorf("delete %s: %w", key, err)
			}
			fmt.Printf("Deleted %s\n", key)
			continue
		}

		if strings.TrimSpace(issue.Key) == "" {
			key, err := createIssue(ctx, client, cfg, issue)
			if err != nil {
				return fmt.Errorf("create issue: %w", err)
			}
			fmt.Printf("Created %s\n", key)
			continue
		} else {
			if err := updateIssue(ctx, client, issue); err != nil {
				return fmt.Errorf("update %s: %w", issue.Key, err)
			}
			fmt.Printf("Updated %s\n", issue.Key)
		}
		remaining = append(remaining, issue)
	}

	if len(remaining) != len(data.Issues) {
		data.Issues = remaining
		if err := writeIssueFile(cfg.YAMLPath, data); err != nil {
			return err
		}
	}
	return nil
}

func createIssue(ctx context.Context, client *jiraClient, cfg config, issue issueRecord) (string, error) {
	summary := strings.TrimSpace(issue.Summary)
	if summary == "" {
		return "", errors.New("summary is required to create a Jira issue")
	}

	issueType := strings.TrimSpace(issue.IssueType)
	if issueType == "" {
		issueType = cfg.DefaultIssueType
	}

	issueTypeField, err := client.issueTypeField(ctx, issueType)
	if err != nil {
		return "", fmt.Errorf("resolve issue type %q: %w", issueType, err)
	}

	fields := map[string]interface{}{
		"project":   map[string]string{"key": cfg.ProjectKey},
		"summary":   summary,
		"issuetype": issueTypeField,
	}

	if desc := strings.TrimSpace(issue.Description); desc != "" {
		fields["description"] = plainTextToADF(desc)
	}
	if issue.Labels != nil {
		fields["labels"] = issue.Labels
	}
	if id := strings.TrimSpace(issue.AssigneeAccountID); id != "" {
		fields["assignee"] = map[string]string{"accountId": id}
	}
	priority := strings.TrimSpace(issue.Priority)
	if priority != "" {
		fields["priority"] = map[string]string{"name": priority}
	}
	parent := strings.TrimSpace(issue.ParentKey)
	parentAllowed := parent != "" && canSetParent(issueType)
	if parentAllowed {
		fields["parent"] = map[string]string{"key": parent}
	}

	key, err := client.createIssue(ctx, fields)
	if err != nil && priority != "" && isPriorityError(err) {
		delete(fields, "priority")
		key, err = client.createIssue(ctx, fields)
		if err == nil {
			fmt.Printf("Warning: Jira rejected priority for new issue %q; created without priority.\n", summary)
		}
	}
	if err != nil && parentAllowed && isParentError(err) {
		delete(fields, "parent")
		key, err = client.createIssue(ctx, fields)
		if err == nil {
			fmt.Printf("Warning: Jira rejected parent %s for new issue %q; created without parent.\n", parent, summary)
		}
	}
	return key, err
}

func updateIssue(ctx context.Context, client *jiraClient, issue issueRecord) error {
	summary := strings.TrimSpace(issue.Summary)
	if summary == "" {
		return errors.New("summary cannot be empty when updating an issue")
	}

	fields := map[string]interface{}{
		"summary":     summary,
		"description": plainTextToADF(strings.TrimSpace(issue.Description)),
	}

	issueType := strings.TrimSpace(issue.IssueType)
	if issue.ForceIssueType && issueType != "" {
		issueTypeField, err := client.issueTypeField(ctx, issueType)
		if err != nil {
			return fmt.Errorf("resolve issue type %q: %w", issueType, err)
		}
		fields["issuetype"] = issueTypeField
	}

	if issue.Labels != nil {
		fields["labels"] = issue.Labels
	}
	if id := strings.TrimSpace(issue.AssigneeAccountID); id != "" {
		fields["assignee"] = map[string]string{"accountId": id}
	}
	priority := strings.TrimSpace(issue.Priority)
	if priority != "" {
		fields["priority"] = map[string]string{"name": priority}
	}
	parent := strings.TrimSpace(issue.ParentKey)
	parentAllowed := parent != "" && canSetParent(issueType)
	if parentAllowed {
		fields["parent"] = map[string]string{"key": parent}
	}

	err := client.updateIssue(ctx, issue.Key, fields)
	if err != nil && priority != "" && isPriorityError(err) {
		delete(fields, "priority")
		err = client.updateIssue(ctx, issue.Key, fields)
		if err == nil {
			fmt.Printf("Warning: Jira rejected priority update for %s; left existing priority unchanged.\n", issue.Key)
		}
	}
	if err != nil && parentAllowed && isParentError(err) {
		delete(fields, "parent")
		err = client.updateIssue(ctx, issue.Key, fields)
		if err == nil {
			fmt.Printf("Warning: Jira rejected parent update %s for %s; left parent unchanged.\n", parent, issue.Key)
		}
	}
	return err
}

func (c *jiraClient) deleteIssue(ctx context.Context, key string) error {
	req, err := c.newRequest(ctx, http.MethodDelete, jiraAPIPrefix+"/issue/"+key, nil, nil)
	if err != nil {
		return err
	}
	return c.do(req, nil)
}

func (c *jiraClient) issueTypeField(ctx context.Context, name string) (map[string]string, error) {
	clean := strings.TrimSpace(name)
	if clean == "" {
		return nil, errors.New("issue type name is required")
	}

	if id, ok, err := c.lookupIssueTypeID(ctx, clean); err != nil {
		return nil, err
	} else if ok {
		return map[string]string{"id": id}, nil
	}

	return map[string]string{"name": clean}, nil
}

func (c *jiraClient) lookupIssueTypeID(ctx context.Context, name string) (string, bool, error) {
	normalized := normalizeIssueTypeName(name)
	if normalized == "" {
		return "", false, nil
	}

	c.issueTypeMu.Lock()
	if c.issueTypeCache != nil {
		if id, ok := c.issueTypeCache[normalized]; ok {
			c.issueTypeMu.Unlock()
			return id, true, nil
		}
	}
	c.issueTypeMu.Unlock()

	req, err := c.newRequest(ctx, http.MethodGet, jiraAPIPrefix+"/issuetype", nil, nil)
	if err != nil {
		return "", false, err
	}

	var payload []struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if err := c.do(req, &payload); err != nil {
		return "", false, err
	}

	table := make(map[string]string, len(payload))
	for _, item := range payload {
		key := normalizeIssueTypeName(item.Name)
		if key == "" {
			continue
		}
		table[key] = item.ID
	}

	c.issueTypeMu.Lock()
	if c.issueTypeCache == nil {
		c.issueTypeCache = table
	} else {
		for k, v := range table {
			c.issueTypeCache[k] = v
		}
	}
	result, ok := c.issueTypeCache[normalized]
	c.issueTypeMu.Unlock()
	return result, ok, nil
}

func normalizeIssueTypeName(name string) string {
	clean := strings.ToLower(strings.TrimSpace(name))
	if clean == "" {
		return ""
	}
	clean = strings.ReplaceAll(clean, " ", "")
	clean = strings.ReplaceAll(clean, "-", "")
	return clean
}

func isParentError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "parent")
}

func canSetParent(issueType string) bool {
	return normalizeIssueTypeName(issueType) == "subtask"
}

func isPriorityError(err error) bool {
	if err == nil {
		return false
	}
	msg := strings.ToLower(err.Error())
	return strings.Contains(msg, "priority")
}

func writeIssueFile(path string, data issueFile) error {
	if data.Issues == nil {
		data.Issues = []issueRecord{}
	}
	output, err := yaml.Marshal(data)
	if err != nil {
		return fmt.Errorf("marshal yaml: %w", err)
	}

	dir := filepath.Dir(path)
	if dir != "." && dir != "" {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("create directory %s: %w", dir, err)
		}
	}

	if err := os.WriteFile(path, output, 0o644); err != nil {
		return fmt.Errorf("write yaml: %w", err)
	}
	return nil
}

func readIssueFile(path string) (issueFile, error) {
	content, err := os.ReadFile(path)
	if err != nil {
		return issueFile{}, fmt.Errorf("read yaml: %w", err)
	}
	var data issueFile
	if err := yaml.Unmarshal(content, &data); err != nil {
		return issueFile{}, fmt.Errorf("parse yaml: %w", err)
	}
	return data, nil
}

type adfNode struct {
	Type    string    `json:"type"`
	Text    string    `json:"text,omitempty"`
	Content []adfNode `json:"content,omitempty"`
}

func adfToPlainText(raw json.RawMessage) (string, error) {
	if len(raw) == 0 || string(raw) == "null" {
		return "", nil
	}
	var node adfNode
	if err := json.Unmarshal(raw, &node); err != nil {
		return "", err
	}
	var sb strings.Builder
	ctx := &adfContext{}
	appendADFNode(&sb, node, ctx)
	text := strings.TrimRight(sb.String(), "\n")
	return text, nil
}

type adfContext struct {
	listStack          []listState
	pendingPrefix      string
	continuationPrefix string
}

type listState struct {
	ordered bool
	counter int
}

func (ctx *adfContext) pushList(ordered bool) {
	ctx.listStack = append(ctx.listStack, listState{ordered: ordered})
}

func (ctx *adfContext) popList() {
	if len(ctx.listStack) == 0 {
		return
	}
	ctx.listStack = ctx.listStack[:len(ctx.listStack)-1]
}

func (ctx *adfContext) nextListPrefix() string {
	if len(ctx.listStack) == 0 {
		return ""
	}
	indent := strings.Repeat("  ", len(ctx.listStack)-1)
	idx := len(ctx.listStack) - 1
	state := ctx.listStack[idx]
	if state.ordered {
		state.counter++
		ctx.listStack[idx] = state
		return fmt.Sprintf("%s%d. ", indent, state.counter)
	}
	return fmt.Sprintf("%s- ", indent)
}

func (ctx *adfContext) startLine(prefix string) {
	ctx.pendingPrefix = prefix
	if prefix != "" {
		ctx.continuationPrefix = strings.Repeat(" ", len(prefix))
	}
}

func (ctx *adfContext) ensurePrefix(sb *strings.Builder) {
	if ctx.pendingPrefix != "" {
		sb.WriteString(ctx.pendingPrefix)
		ctx.pendingPrefix = ""
	}
}

func (ctx *adfContext) newline(sb *strings.Builder) {
	sb.WriteString("\n")
	if ctx.continuationPrefix != "" {
		ctx.pendingPrefix = ctx.continuationPrefix
	}
}

func (ctx *adfContext) clearContinuation() {
	ctx.continuationPrefix = ""
	ctx.pendingPrefix = ""
}

func appendADFNode(sb *strings.Builder, node adfNode, ctx *adfContext) {
	switch node.Type {
	case "doc":
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
	case "paragraph", "heading":
		ctx.ensurePrefix(sb)
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
		ctx.newline(sb)
		ctx.clearContinuation()
	case "text":
		ctx.ensurePrefix(sb)
		sb.WriteString(node.Text)
	case "hardBreak":
		ctx.newline(sb)
	case "bulletList":
		ctx.pushList(false)
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
		ctx.popList()
		ctx.clearContinuation()
	case "orderedList":
		ctx.pushList(true)
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
		ctx.popList()
		ctx.clearContinuation()
	case "listItem":
		prefix := ctx.nextListPrefix()
		ctx.startLine(prefix)
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
		ctx.newline(sb)
		ctx.clearContinuation()
	case "blockquote":
		ctx.startLine("> ")
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
		ctx.newline(sb)
		ctx.clearContinuation()
	default:
		for _, child := range node.Content {
			appendADFNode(sb, child, ctx)
		}
	}
}

func plainTextToADF(input string) map[string]interface{} {
	normalized := strings.ReplaceAll(input, "\r\n", "\n")
	sections := strings.Split(normalized, "\n\n")
	content := make([]map[string]interface{}, 0, len(sections))
	for _, section := range sections {
		lines := strings.Split(section, "\n")
		var nodes []map[string]interface{}
		for i, line := range lines {
			trimmed := strings.TrimRight(line, " ")
			if trimmed != "" {
				nodes = append(nodes, map[string]interface{}{
					"type": "text",
					"text": trimmed,
				})
			}
			if i < len(lines)-1 {
				nodes = append(nodes, map[string]interface{}{"type": "hardBreak"})
			}
		}
		paragraph := map[string]interface{}{"type": "paragraph"}
		if len(nodes) > 0 {
			paragraph["content"] = nodes
		}
		content = append(content, paragraph)
	}
	if len(content) == 0 {
		content = append(content, map[string]interface{}{"type": "paragraph"})
	}
	return map[string]interface{}{
		"type":    "doc",
		"version": 1,
		"content": content,
	}
}
