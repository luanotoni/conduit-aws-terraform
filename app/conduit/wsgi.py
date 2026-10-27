"""
WSGI config for conduit project.

It exposes the WSGI callable as a module-level variable named ``application``.

For more information on this file, see
https://docs.djangoproject.com/en/1.10/howto/deployment/wsgi/
"""

import os

from django.core.wsgi import get_wsgi_application

from conduit.apps.core.tracing import configure_tracing

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "conduit.settings")

# Before the app is built: the Django instrumentor hooks in via MIDDLEWARE.
configure_tracing()

application = get_wsgi_application()
