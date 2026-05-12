#!/usr/bin/env bash
# =============================================================================
# StatusPulse — Health Monitor Script
# Designed to run as a cron job every 5 minutes
# Cron entry: */5 * * * * /home/deploy/statuspulse/scripts/health-monitor.sh
# =============================================================================

set -uo pipefail

# --- Configuration -----------------------------------------------------------
HEALTH_URL="${HEALTH_URL:-https://localhost/health}"
DOMAIN="${DOMAIN:-localhost}"
ALERT_WEBHOOK_URL="${ALERT_WEBHOOK_URL:-}"
LOG_FILE="/var/log/statuspulse-monitor.log"
DISK_THRESHOLD=80
MEMORY_THRESHOLD=90
CERT_WARN_DAYS=14
EXPECTED_CONTAINERS=("statuspulse-app" "statuspulse-db" "statuspulse-redis")

# --- Logging -----------------------------------------------------------------
log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo "$msg"
    echo "$msg" >> "$LOG_FILE" 2>/dev/null || true
}

# --- Alert function ----------------------------------------------------------
send_alert() {
    local title="$1"
    local message="$2"
    local level="${3:-warning}"  # info, warning, critical

    log "🚨 ALERT [$level]: $title — $message"

    if [ -n "$ALERT_WEBHOOK_URL" ]; then
        local payload
        payload=$(cat <<EOF
{
  "text": "🚨 StatusPulse Alert [$level]",
  "blocks": [
    {
      "type": "section",
      "text": {
        "type": "mrkdwn",
        "text": "*${title}*\n${message}\n_Host:_ $(hostname)\n_Time:_ $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
      }
    }
  ]
}
EOF
        )
        curl -sf -X POST "$ALERT_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$payload" \
            --max-time 10 > /dev/null 2>&1 || \
            log "⚠️  Failed to send webhook alert"
    else
        log "⚠️  ALERT_WEBHOOK_URL not set — alert not sent externally"
    fi
}

# --- Checks ------------------------------------------------------------------
log "========================================="
log "🔍 StatusPulse Health Monitor — Starting checks"
log "========================================="

ALERTS=0

# 1. Check /health endpoint
log "1️⃣  Checking /health endpoint..."
HTTP_RESPONSE=$(curl -sf --max-time 10 "$HEALTH_URL" 2>/dev/null) || HTTP_RESPONSE=""
HTTP_CODE=$(curl -sf -o /dev/null -w "%{http_code}" --max-time 10 "$HEALTH_URL" 2>/dev/null) || HTTP_CODE="000"

if [ "$HTTP_CODE" = "200" ]; then
    # Validate JSON
    if echo "$HTTP_RESPONSE" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
        log "   ✅ /health — HTTP $HTTP_CODE, valid JSON"
    else
        log "   ⚠️  /health — HTTP $HTTP_CODE, but response is NOT valid JSON"
        send_alert "Health endpoint returning invalid JSON" "HTTP $HTTP_CODE but malformed response" "warning"
        ALERTS=$((ALERTS + 1))
    fi
else
    log "   ❌ /health — HTTP $HTTP_CODE"
    send_alert "Health endpoint DOWN" "/health returned HTTP $HTTP_CODE" "critical"
    ALERTS=$((ALERTS + 1))
fi

# 2. Check disk usage
log "2️⃣  Checking disk usage..."
DISK_USAGE=$(df -h / | awk 'NR==2 {gsub("%",""); print $5}' 2>/dev/null || echo "0")
if [ "$DISK_USAGE" -gt "$DISK_THRESHOLD" ]; then
    log "   ⚠️  Disk usage: ${DISK_USAGE}% (threshold: ${DISK_THRESHOLD}%)"
    send_alert "High disk usage" "Disk is ${DISK_USAGE}% full (threshold: ${DISK_THRESHOLD}%)" "warning"
    ALERTS=$((ALERTS + 1))
else
    log "   ✅ Disk usage: ${DISK_USAGE}%"
fi

# 3. Check memory usage
log "3️⃣  Checking memory usage..."
if command -v free &>/dev/null; then
    MEMORY_USAGE=$(free | awk 'NR==2 {printf "%.0f", $3/$2 * 100}' 2>/dev/null || echo "0")
else
    # macOS fallback
    MEMORY_USAGE=$(vm_stat | awk '
        /Pages active/ {active=$3}
        /Pages wired/ {wired=$4}
        /Pages free/ {free=$3}
        /Pages speculative/ {spec=$3}
        END {
            gsub(/\./,"",active); gsub(/\./,"",wired);
            gsub(/\./,"",free); gsub(/\./,"",spec);
            total=active+wired+free+spec;
            if(total>0) printf "%.0f", (active+wired)/total*100;
            else print "0"
        }' 2>/dev/null || echo "0")
fi

if [ "$MEMORY_USAGE" -gt "$MEMORY_THRESHOLD" ]; then
    log "   ⚠️  Memory usage: ${MEMORY_USAGE}% (threshold: ${MEMORY_THRESHOLD}%)"
    send_alert "High memory usage" "Memory is ${MEMORY_USAGE}% used (threshold: ${MEMORY_THRESHOLD}%)" "warning"
    ALERTS=$((ALERTS + 1))
else
    log "   ✅ Memory usage: ${MEMORY_USAGE}%"
fi

# 4. Check Docker containers
log "4️⃣  Checking Docker containers..."
for container in "${EXPECTED_CONTAINERS[@]}"; do
    STATUS=$(docker inspect --format='{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")
    if [ "$STATUS" = "running" ]; then
        log "   ✅ $container — running"
    else
        log "   ❌ $container — $STATUS"
        send_alert "Container not running" "$container status: $STATUS" "critical"
        ALERTS=$((ALERTS + 1))
    fi
done

# 5. Check TLS certificate expiry
log "5️⃣  Checking TLS certificate..."
if command -v openssl &>/dev/null && [ "$DOMAIN" != "localhost" ]; then
    CERT_EXPIRY=$(echo | openssl s_client -servername "$DOMAIN" -connect "$DOMAIN":443 2>/dev/null | \
        openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)

    if [ -n "$CERT_EXPIRY" ]; then
        CERT_EXPIRY_EPOCH=$(date -d "$CERT_EXPIRY" +%s 2>/dev/null || date -jf "%b %d %H:%M:%S %Y %Z" "$CERT_EXPIRY" +%s 2>/dev/null || echo "0")
        NOW_EPOCH=$(date +%s)
        DAYS_LEFT=$(( (CERT_EXPIRY_EPOCH - NOW_EPOCH) / 86400 ))

        if [ "$DAYS_LEFT" -lt "$CERT_WARN_DAYS" ]; then
            log "   ⚠️  TLS certificate expires in ${DAYS_LEFT} days (${CERT_EXPIRY})"
            send_alert "TLS certificate expiring soon" "Expires in ${DAYS_LEFT} days on ${CERT_EXPIRY}" "warning"
            ALERTS=$((ALERTS + 1))
        else
            log "   ✅ TLS certificate valid — ${DAYS_LEFT} days remaining"
        fi
    else
        log "   ⚠️  Could not retrieve TLS certificate info"
    fi
else
    log "   ℹ️  Skipping TLS check (localhost or openssl not available)"
fi

# --- Summary -----------------------------------------------------------------
log ""
if [ "$ALERTS" -eq 0 ]; then
    log "✅ All checks passed — no alerts"
else
    log "⚠️  ${ALERTS} alert(s) triggered"
fi
log "========================================="
