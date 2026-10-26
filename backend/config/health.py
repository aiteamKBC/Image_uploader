"""Health check endpoint for load balancers (AWS ALB / ECS).

Implemented as a WSGI wrapper around the Django app (see wsgi.py), so it answers
before Django and any middleware run: the ALB health checker calls the task's
private IP, which is never listed in ALLOWED_HOSTS. Even the first middleware is
too late, because OpenTelemetry inserts its own middleware ahead of it and that
one reads (and validates) the Host header, turning every health check into a 400.
"""


def with_health_check(app):
    def application(environ, start_response):
        if environ.get("PATH_INFO") == "/health/":
            start_response("200 OK", [("Content-Type", "text/plain")])
            return [b"ok"]
        return app(environ, start_response)

    return application
