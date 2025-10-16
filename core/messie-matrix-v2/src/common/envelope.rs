use serde::Serialize;

#[derive(Debug, Serialize)]
struct ErrorPayload<'a> {
    code: &'a str,
    message: String,
}

#[derive(Debug, Serialize)]
#[serde(untagged)]
enum Envelope<T: Serialize> {
    Ok { ok: bool, data: T },
    Ack { ok: bool },
    Err { ok: bool, error: ErrorPayload<'static> },
}

pub fn ok_json<T: Serialize>(data: T) -> String {
    serde_json::to_string(&Envelope::Ok { ok: true, data })
        .unwrap_or_else(|e| err_json("sdk_error", format!("serialize: {e}")))
}
pub fn ack_json() -> String {
    serde_json::to_string(&Envelope::<()>::Ack { ok: true })
        .unwrap_or_else(|e| err_json("sdk_error", format!("serialize: {e}")))
}
pub fn err_json(code: &'static str, message: impl ToString) -> String {
    serde_json::to_string(&Envelope::<()>::Err { ok: false, error: ErrorPayload { code, message: message.to_string() } })
        .unwrap_or_else(|_| "{\"ok\":false,\"error\":{\"code\":\"unknown\",\"message\":\"unknown error\"}}".to_string())
}

