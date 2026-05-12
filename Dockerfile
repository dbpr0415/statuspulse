# =============================================================================
# StatusPulse — Production Dockerfile
# Multi-stage build | Non-root user | Optimized layer caching | HEALTHCHECK
# =============================================================================

# ---------------------------------------------------------------------------
# Stage 1: Builder — compile dependencies on Alpine
# ---------------------------------------------------------------------------
FROM python:3.11-alpine AS builder

WORKDIR /build

# Install build dependencies needed for psycopg2-binary
RUN apk add --no-cache gcc musl-dev libffi-dev

# Install only the requirements first (layer caching optimisation).
COPY app/requirements.txt .

RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# ---------------------------------------------------------------------------
# Stage 2: Runtime — minimal Alpine image
# ---------------------------------------------------------------------------
FROM python:3.11-alpine AS runtime

# Install runtime dependency for psycopg2 (libpq)
RUN apk add --no-cache libpq

# Copy pre-built Python packages from the builder stage
COPY --from=builder /install /usr/local

# Create a non-root user and group
RUN addgroup -S appgroup \
    && adduser -S appuser -G appgroup

WORKDIR /app

# Copy application code (after dependencies — better layer caching)
COPY app/ .

# Create a small healthcheck script using Python stdlib (no curl needed)
RUN printf '#!/usr/bin/env python3\nimport urllib.request, sys\ntry:\n    r = urllib.request.urlopen("http://localhost:8000/health", timeout=5)\n    sys.exit(0 if r.status == 200 else 1)\nexcept Exception:\n    sys.exit(1)\n' > /app/healthcheck.py \
    && chmod +x /app/healthcheck.py

# Switch to the non-root user
USER appuser

# Expose the application port
EXPOSE 8000

# HEALTHCHECK — Docker uses this to determine container health
HEALTHCHECK --interval=30s --timeout=10s --start-period=15s --retries=3 \
    CMD python3 /app/healthcheck.py

# Run with gunicorn + uvicorn workers for production
CMD ["gunicorn", "main:app", \
     "--workers", "2", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
