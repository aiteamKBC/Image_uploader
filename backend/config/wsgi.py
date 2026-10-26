"""
WSGI config for config project.

It exposes the WSGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/6.0/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application

from config.health import with_health_check

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')

# /health/ is answered before Django runs (see config/health.py)
application = with_health_check(get_wsgi_application())
