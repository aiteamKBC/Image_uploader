"""Health check endpoint for load balancers (AWS ALB / ECS).

Implemented as middleware placed first in MIDDLEWARE so it answers before
Django validates the Host header: the ALB health checker calls the task's
private IP, which is never listed in ALLOWED_HOSTS and would get a 400.
"""

from django.http import HttpResponse


class HealthCheckMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path == "/health/":
            return HttpResponse("ok", content_type="text/plain")
        return self.get_response(request)
