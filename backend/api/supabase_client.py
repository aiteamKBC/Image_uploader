"""Thin helper that builds a single, reusable Supabase client.

Credentials are read from ``backend/.env`` (see config/settings.py) so they
never live in the frontend or in source control.
"""

from functools import lru_cache

from django.conf import settings
from supabase import Client, create_client


@lru_cache(maxsize=1)
def get_supabase() -> Client:
    """Return a cached Supabase client, creating it on first use."""
    if not settings.SUPABASE_URL or not settings.SUPABASE_KEY:
        raise RuntimeError(
            "SUPABASE_URL / SUPABASE_KEY are missing. Add them to backend/.env"
        )
    return create_client(settings.SUPABASE_URL, settings.SUPABASE_KEY)
