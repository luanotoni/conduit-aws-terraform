import json

from django.test import TestCase


class HealthcheckTests(TestCase):
    def test_healthz_returns_ok(self):
        response = self.client.get("/healthz")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"status": "ok"})

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

    def test_authenticated_endpoint_rejects_missing_token(self):
        response = self.client.get("/api/user/")
        self.assertEqual(response.status_code, 403)
