"""Structured request logging.

Every log line is a single JSON object so CloudWatch Logs Insights can query
fields directly and metric filters (see infra/terraform/modules/monitoring)
can turn them into metrics. Each request gets a request id, taken from the
ALB's X-Amzn-Trace-Id when present so app logs can be joined with ALB/WAF
logs, and every line logged while handling that request carries it, plus
the OpenTelemetry trace id when tracing is on (see tracing.py), so a log line
leads straight to its trace in SigNoz.
"""

import contextvars
import json
import logging
import time
import uuid

from opentelemetry import trace

request_id_var = contextvars.ContextVar("request_id", default=None)

# Attributes every LogRecord has; anything else was passed via `extra=`.
_RESERVED = set(vars(logging.makeLogRecord({}))) | {"message", "asctime"}


class RequestIdFilter(logging.Filter):
    def filter(self, record):
        record.request_id = request_id_var.get()
        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            record.trace_id = trace.format_trace_id(span_context.trace_id)
            record.span_id = trace.format_span_id(span_context.span_id)
        return True


class JsonFormatter(logging.Formatter):
    converter = time.gmtime

    def format(self, record):
        timestamp = self.formatTime(record, "%Y-%m-%dT%H:%M:%S")
        payload = {
            "timestamp": f"{timestamp}.{int(record.msecs):03d}Z",
            "level": record.levelname,
            "logger": record.name,
            "message": record.getMessage(),
        }
        for key, value in vars(record).items():
            if key not in _RESERVED and value is not None:
                payload[key] = value
        if record.exc_info:
            payload["exception"] = self.formatException(record.exc_info)
        return json.dumps(payload, default=str)


logger = logging.getLogger("conduit.request")


class RequestLogMiddleware:
    """Logs one `request` event per request with status and duration."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_id = (
            request.headers.get("X-Amzn-Trace-Id")
            or request.headers.get("X-Request-Id")
            or uuid.uuid4().hex
        )[:128]
        token = request_id_var.set(request_id)
        start = time.perf_counter()
        try:
            response = self.get_response(request)
            response["X-Request-Id"] = request_id
            self._log(request, response.status_code, start)
            return response
        finally:
            request_id_var.reset(token)

    @staticmethod
    def _log(request, status, start):
        match = request.resolver_match
        user = getattr(request, "user", None)
        logger.info(
            "request",
            extra={
                "method": request.method,
                "path": request.path,
                # Route pattern, not the raw path: low cardinality, so it can be
                # grouped on without one bucket per article slug.
                "route": match.route if match else None,
                "status": status,
                "duration_ms": round((time.perf_counter() - start) * 1000, 2),
                "user_id": user.pk if user is not None and user.is_authenticated else None,
            },
        )
