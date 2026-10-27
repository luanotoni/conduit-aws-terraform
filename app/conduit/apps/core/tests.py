import json
import logging

from django.test import TestCase
from opentelemetry.sdk.trace import TracerProvider

from conduit.apps.core.observability import JsonFormatter, RequestIdFilter, request_id_var


class HealthcheckTests(TestCase):
    def test_healthz_returns_ok(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

    def test_healthz_accepts_task_private_ip_as_host(self):
        """The ALB health checker sends the task IP as Host, not the ALB DNS."""
        with self.settings(ALLOWED_HOSTS=["example-alb.elb.amazonaws.com"]):
            response = self.client.get("/healthz", HTTP_HOST="10.0.10.38:8000")
            self.assertEqual(response.status_code, 200)

            other = self.client.get("/api/tags", HTTP_HOST="10.0.10.38:8000")
            self.assertEqual(other.status_code, 400)

    def test_tags_returns_the_realworld_response_shape(self):
        """The external frontend loads this endpoint on its home page."""
        response = self.client.get("/api/tags")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"tags": []})


class AuthFlowSmokeTests(TestCase):
    """
    End-to-end smoke test for the flow that matters most: can a user sign up,
    log in, and use the resulting JWT to hit an authenticated endpoint.

    The original 2017 tutorial repo shipped with zero tests. This is the
    minimum needed so the CI pipeline has something real to fail on before a
    deploy ever reaches ECS, instead of only trusting `manage.py check`.
    """

    def test_register_login_and_authenticated_request(self):
        register_response = self.client.post(
            "/api/users/",
            data=json.dumps(
                {
                    "user": {
                        "username": "smoketest",
                        "email": "smoke@test.com",
                        "password": "supersecret123",
                    }
                }
            ),
            content_type="application/json",
        )
        self.assertEqual(register_response.status_code, 201)

        login_response = self.client.post(
            "/api/users/login/",
            data=json.dumps(
                {"user": {"email": "smoke@test.com", "password": "supersecret123"}}
            ),
            content_type="application/json",
        )
        self.assertEqual(login_response.status_code, 200)
        token = login_response.json()["user"]["token"]

        me_response = self.client.get(
            "/api/user/", HTTP_AUTHORIZATION=f"Token {token}"
        )
        self.assertEqual(me_response.status_code, 200)
        self.assertEqual(me_response.json()["user"]["email"], "smoke@test.com")

        # This endpoint must be evaluated before the generic
        # /api/articles/:slug route; the frontend loads it after login.
        feed_response = self.client.get(
            "/api/articles/feed?limit=10&offset=0",
            HTTP_AUTHORIZATION=f"Token {token}",
        )
        self.assertEqual(feed_response.status_code, 200)
        self.assertEqual(feed_response.json()["articles"], [])

        article_response = self.client.post(
            "/api/articles",
            data=json.dumps(
                {
                    "article": {
                        "title": "Smoke test article",
                        "description": "Checks the authenticated article flow.",
                        "body": "Smoke test body.",
                        "tagList": ["smoke"],
                    }
                }
            ),
            content_type="application/json",
            HTTP_AUTHORIZATION=f"Token {token}",
        )
        self.assertEqual(article_response.status_code, 201)
        self.assertTrue(article_response.json()["article"]["slug"])

        profile_response = self.client.get(
            "/api/profiles/smoketest", HTTP_AUTHORIZATION=f"Token {token}"
        )
        self.assertEqual(profile_response.status_code, 200)
        self.assertEqual(profile_response.json()["profile"]["username"], "smoketest")
        # No third-party placeholder URL: the frontend renders its own avatar.
        self.assertIsNone(profile_response.json()["profile"]["image"])

        slug = article_response.json()["article"]["slug"]
        favorite_response = self.client.post(
            f"/api/articles/{slug}/favorite", HTTP_AUTHORIZATION=f"Token {token}"
        )
        self.assertEqual(favorite_response.status_code, 201)
        self.assertTrue(favorite_response.json()["article"]["favorited"])
        self.assertEqual(favorite_response.json()["article"]["favoritesCount"], 1)

        unfavorite_response = self.client.delete(
            f"/api/articles/{slug}/favorite", HTTP_AUTHORIZATION=f"Token {token}"
        )
        self.assertEqual(unfavorite_response.status_code, 200)
        self.assertFalse(unfavorite_response.json()["article"]["favorited"])

    def test_settings_update_persists_profile_image(self):
        register = self.client.post(
            "/api/users/",
            data=json.dumps(
                {"user": {"username": "img", "email": "img@test.com", "password": "supersecret123"}}
            ),
            content_type="application/json",
        )
        token = register.json()["user"]["token"]
        auth = {"HTTP_AUTHORIZATION": f"Token {token}"}
        image = "https://example.com/me.png"

        update = self.client.put(
            "/api/user",
            data=json.dumps({"user": {"image": image, "bio": "hi"}}),
            content_type="application/json",
            **auth,
        )
        self.assertEqual(update.status_code, 200)
        self.assertEqual(update.json()["user"]["image"], image)
        self.assertEqual(
            self.client.get("/api/profiles/img").json()["profile"]["image"], image
        )

        cleared = self.client.put(
            "/api/user",
            data=json.dumps({"user": {"image": ""}}),
            content_type="application/json",
            **auth,
        )
        self.assertEqual(cleared.status_code, 200)
        self.assertIsNone(cleared.json()["user"]["image"])

    def test_authenticated_endpoint_rejects_missing_token(self):
        response = self.client.get("/api/user/")
        self.assertEqual(response.status_code, 403)


class RequestLogTests(TestCase):
    def test_request_is_logged_as_structured_event(self):
        with self.assertLogs("conduit.request", level="INFO") as logs:
            response = self.client.get(
                "/api/tags", HTTP_X_AMZN_TRACE_ID="Root=1-abc-def"
            )
        self.assertEqual(response["X-Request-Id"], "Root=1-abc-def")
        record = logs.records[0]
        self.assertEqual(record.status, 200)
        self.assertEqual(record.method, "GET")
        self.assertEqual(record.route, "^api/tags/?$")
        self.assertGreaterEqual(record.duration_ms, 0)

    def test_healthcheck_is_not_logged(self):
        with self.assertNoLogs("conduit.request"):
            self.client.get("/healthz")

    def test_json_formatter_includes_request_context(self):
        token = request_id_var.set("req-1")
        try:
            record = logging.makeLogRecord(
                {"name": "x", "levelname": "INFO", "msg": "hi", "status": 500}
            )
            RequestIdFilter().filter(record)
        finally:
            request_id_var.reset(token)
        line = json.loads(JsonFormatter().format(record))
        self.assertEqual(line["message"], "hi")
        self.assertEqual(line["status"], 500)
        self.assertEqual(line["request_id"], "req-1")

    def test_log_carries_the_active_trace_id(self):
        tracer = TracerProvider().get_tracer(__name__)
        with tracer.start_as_current_span("request") as span:
            record = logging.makeLogRecord({"msg": "hi"})
            RequestIdFilter().filter(record)
        line = json.loads(JsonFormatter().format(record))
        self.assertEqual(line["trace_id"], f"{span.get_span_context().trace_id:032x}")

    def test_log_has_no_trace_id_outside_a_span(self):
        record = logging.makeLogRecord({"msg": "hi"})
        RequestIdFilter().filter(record)
        self.assertNotIn("trace_id", json.loads(JsonFormatter().format(record)))
