use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde_json::json;

#[derive(Debug)]
pub enum ApiError {
    Unauthorized,
    InvalidCredentials,
    Forbidden(String),
    StepUpRequired,
    NotFound,
    BadRequest(String),
    Conflict(String),
    TooManyRequests(u64),
    Internal(String),
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            ApiError::Unauthorized => (
                StatusCode::UNAUTHORIZED,
                "unauthorized",
                "Authentication required.".to_string(),
            ),
            ApiError::InvalidCredentials => (
                StatusCode::UNAUTHORIZED,
                "invalid_credentials",
                "Wrong username or password.".to_string(),
            ),
            ApiError::Forbidden(m) => (StatusCode::FORBIDDEN, "forbidden", m),
            ApiError::StepUpRequired => (
                StatusCode::FORBIDDEN,
                "step_up_required",
                "This action needs your password again to confirm.".to_string(),
            ),
            ApiError::NotFound => (StatusCode::NOT_FOUND, "not_found", "Not found.".to_string()),
            ApiError::BadRequest(m) => (StatusCode::BAD_REQUEST, "bad_request", m),
            ApiError::Conflict(m) => (StatusCode::CONFLICT, "conflict", m),
            ApiError::TooManyRequests(wait) => (
                StatusCode::TOO_MANY_REQUESTS,
                "rate_limited",
                format!("Too many failed attempts. Try again in {wait} seconds."),
            ),
            ApiError::Internal(detail) => {
                // Detail stays in the server log; clients get a generic message.
                tracing::error!(%detail, "internal error");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    "internal",
                    "Internal server error.".to_string(),
                )
            }
        };
        (status, Json(json!({ "error": code, "message": message }))).into_response()
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(e: rusqlite::Error) -> Self {
        ApiError::Internal(format!("database: {e}"))
    }
}
