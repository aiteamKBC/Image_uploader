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

