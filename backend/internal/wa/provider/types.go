package provider

// LoginStep is an interface implemented by all typed login steps.
type LoginStep interface{ StepType() string }

// Typed representations of login step responses we expose upstream.

type LoginStepDisplayAndWait struct {
    Type           string                      `json:"type"`
    DisplayAndWait *LoginStepDisplayAndWaitDef `json:"display_and_wait"`
}

func (s *LoginStepDisplayAndWait) StepType() string { return "display_and_wait" }

type LoginStepDisplayAndWaitDef struct {
    Message  *string `json:"message,omitempty"`
    Data     *string `json:"data,omitempty"`
    ImageURL *string `json:"image_url,omitempty"`
}

type LoginStepUserInput struct {
    Type      string                 `json:"type"`
    UserInput *LoginStepUserInputDef `json:"user_input"`
}

func (s *LoginStepUserInput) StepType() string { return "user_input" }

type LoginStepUserInputDef struct {
    Fields []LoginStepUserInputField `json:"fields,omitempty"`
}

type LoginStepUserInputField struct {
    ID     *string `json:"id,omitempty"`
    Label  *string `json:"label,omitempty"`
    Kind   *string `json:"kind,omitempty"`
    Secret *bool   `json:"secret,omitempty"`
}

type LoginStepCookies struct {
    Type    string                 `json:"type"`
    Cookies *LoginStepCookiesDef   `json:"cookies"`
}

func (s *LoginStepCookies) StepType() string { return "cookies" }

type LoginStepCookiesDef struct {
    Names []string `json:"names,omitempty"`
}

type LoginStepComplete struct {
    Type     string                  `json:"type"`
    Complete *LoginStepCompleteDef   `json:"complete"`
}

func (s *LoginStepComplete) StepType() string { return "complete" }

type LoginStepCompleteDef struct {
    UserLoginID *string `json:"user_login_id,omitempty"`
}
