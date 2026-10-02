from conduit.apps.core.views import healthcheck


class HealthCheckMiddleware:
    """Answer the ALB health check before Django validates the Host header.

    The ALB health checker connects straight to each task and sends its
    private IP (e.g. `10.0.10.38:8000`) as the Host header. That IP changes on
    every task and isn't in ALLOWED_HOSTS, so going through CommonMiddleware
    would raise DisallowedHost -> 400 -> the target is marked unhealthy and ECS
    keeps replacing tasks. Must stay first in MIDDLEWARE.
    """

    PATHS = ("/healthz", "/healthz/")

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path in self.PATHS:
            return healthcheck(request)
        return self.get_response(request)
