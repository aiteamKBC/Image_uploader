# ------------------------------------------------------------
# Backend image: Django API served by Gunicorn
# ------------------------------------------------------------

# Base image: official Python 3.14, "slim" variant (Debian with fewer extras = smaller image)
FROM python:3.14-slim

# PYTHONDONTWRITEBYTECODE=1 -> don't create .pyc files inside the container
# PYTHONUNBUFFERED=1        -> print logs immediately so `docker logs` shows them live
# PIP_NO_CACHE_DIR=1        -> don't keep pip's download cache (smaller image)
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1

# All following commands run inside /app (created automatically)
WORKDIR /app

# Copy ONLY requirements first. Docker caches this layer, so if only
# your code changes (not dependencies), the slow pip install is skipped.
COPY requirements.txt .

# Install Python dependencies (Django, supabase, gunicorn, ...)
RUN pip install -r requirements.txt

# Now copy the rest of the backend code (filtered by .dockerignore)
COPY . .

# Create an unprivileged user so the app doesn't run as root.
# If the app is ever exploited, the attacker has limited permissions.
RUN useradd --create-home appuser

# Switch to that user for everything below, including the running app
USER appuser

# The app listens on port 8023 (use this as the ECS "Container port")
EXPOSE 8023

# Start Gunicorn:
#   config.wsgi:application -> the WSGI entry point in backend/config/wsgi.py
#   --bind 0.0.0.0:8023     -> listen on all interfaces so traffic from outside the container reaches it
#   --workers 3             -> 3 processes handle requests in parallel
#   --timeout 300           -> allow requests up to 5 minutes; the 30s default
#                              would kill large (up to 200 MB) uploads mid-transfer
CMD ["gunicorn", "config.wsgi:application", \
     "--bind", "0.0.0.0:8023", \
     "--workers", "3", \
     "--timeout", "300"]

