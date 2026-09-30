from django.http import JsonResponse


def healthcheck(request):
    """Simple liveness/readiness endpoint used by the ALB target group.

    Kept dependency-free on purpose: it must respond fast and never depend on
    the database, so a DB blip doesn't get read as "the whole service is down"
    by the load balancer and trigger unnecessary deregistration.
    """
    return JsonResponse({"status": "ok"})
