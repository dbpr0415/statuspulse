#!/usr/bin/env bash
# =============================================================================
# StatusPulse — Deploy Script
# Zero-downtime deployment with automatic rollback
# Usage: bash scripts/deploy.sh
# =============================================================================

set -euo pipefail

# --- Configuration -----------------------------------------------------------
REGISTRY="${REGISTRY:-ghcr.io}"
IMAGE_NAME="${IMAGE_NAME:-your-github-username/statuspulse}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.prod.yml}"
HEALTH_URL="${HEALTH_URL:-http://localhost:8000/health}"
MAX_RETRIES=10
RETRY_INTERVAL=5
LOG_FILE="/var/log/statuspulse-deploy.log"

# --- Logging -----------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Health check function ---------------------------------------------------
check_health() {
    local url="$1"
    local retries="${2:-$MAX_RETRIES}"

    for i in $(seq 1 "$retries"); do
        HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" "$url" 2>/dev/null || echo "000")
        if [ "$HTTP_CODE" = "200" ]; then
            log "✅ Health check passed (HTTP $HTTP_CODE)"
            return 0
        fi
        log "⏳ Health check attempt $i/$retries — HTTP $HTTP_CODE"
        sleep "$RETRY_INTERVAL"
    done

    log "❌ Health check failed after $retries attempts"
    return 1
}

# --- Main deployment flow ----------------------------------------------------
log "========================================="
log "🚀 Starting deployment"
log "   Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
log "========================================="

# Save the current image tag for rollback
PREVIOUS_IMAGE=$(docker inspect --format='{{.Config.Image}}' statuspulse-app 2>/dev/null || echo "none")
log "📌 Previous image: $PREVIOUS_IMAGE"

# Pull the new image
log "📥 Pulling new image..."
docker pull "${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Update the image reference for docker compose
export APP_IMAGE="${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

# Start the new container (recreate only the app, keep DB and Redis)
log "🔄 Starting new container..."
docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate app

# Wait for health check
log "🏥 Running health check..."
if check_health "$HEALTH_URL"; then
    log "========================================="
    log "✅ Deployment successful!"
    log "   Image: ${REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"
    log "========================================="

    # Clean up old images
    log "🧹 Cleaning up old images..."
    docker image prune -f >> "$LOG_FILE" 2>/dev/null || true

    exit 0
else
    log "========================================="
    log "❌ Deployment failed — rolling back!"
    log "========================================="

    # Rollback to previous image
    if [ "$PREVIOUS_IMAGE" != "none" ]; then
        log "🔄 Rolling back to: $PREVIOUS_IMAGE"
        export APP_IMAGE="$PREVIOUS_IMAGE"
        docker compose -f "$COMPOSE_FILE" up -d --no-deps --force-recreate app

        # Verify rollback
        if check_health "$HEALTH_URL" 5; then
            log "✅ Rollback successful — running on: $PREVIOUS_IMAGE"
        else
            log "🚨 CRITICAL: Rollback also failed! Manual intervention required."
        fi
    else
        log "⚠️  No previous image found for rollback"
    fi

    exit 1
fi
