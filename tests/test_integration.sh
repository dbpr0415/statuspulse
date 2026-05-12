#!/usr/bin/env bash
# =============================================================================
# StatusPulse — Integration Tests
# Tests all API endpoints, verifies status codes and JSON response shapes.
# Exit non-zero on any failure.
# =============================================================================

set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:8000}"
PASSED=0
FAILED=0
TOTAL=0

# --- Helpers ----------------------------------------------------------------

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No colour

log_pass() {
    PASSED=$((PASSED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "${GREEN}✅ PASS${NC} — $1"
}

log_fail() {
    FAILED=$((FAILED + 1))
    TOTAL=$((TOTAL + 1))
    echo -e "${RED}❌ FAIL${NC} — $1: $2"
}

# Wait for the service to be ready (up to 60 seconds)
wait_for_service() {
    echo -e "${YELLOW}⏳ Waiting for StatusPulse to be ready...${NC}"
    for i in $(seq 1 30); do
        if curl -sf "${BASE_URL}/health" > /dev/null 2>&1; then
            echo -e "${GREEN}✅ Service is ready!${NC}"
            return 0
        fi
        sleep 2
    done
    echo -e "${RED}❌ Service did not become ready within 60 seconds${NC}"
    exit 1
}

assert_status() {
    local test_name="$1"
    local expected_status="$2"
    local actual_status="$3"

    if [ "$actual_status" -eq "$expected_status" ]; then
        return 0
    else
        log_fail "$test_name" "Expected HTTP $expected_status, got $actual_status"
        return 1
    fi
}

assert_json_field() {
    local test_name="$1"
    local json="$2"
    local field="$3"

    if echo "$json" | python3 -c "import sys,json; d=json.load(sys.stdin); assert '$field' in (d if isinstance(d,dict) else d[0])" 2>/dev/null; then
        return 0
    else
        log_fail "$test_name" "Missing field '$field' in response"
        return 1
    fi
}

# --- Tests ------------------------------------------------------------------

echo ""
echo "========================================="
echo "  StatusPulse Integration Tests"
echo "  Target: ${BASE_URL}"
echo "========================================="
echo ""

wait_for_service

# 1. GET /health  — expect 200 with status, checks, timestamp
echo "--- Test 1: GET /health ---"
RESPONSE=$(curl -sw "\n%{http_code}" "${BASE_URL}/health" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "GET /health status" 200 "$HTTP_CODE" && \
   assert_json_field "GET /health" "$BODY" "status" && \
   assert_json_field "GET /health" "$BODY" "checks" && \
   assert_json_field "GET /health" "$BODY" "timestamp"; then
    log_pass "GET /health — 200 with correct JSON shape"
fi

# 2. GET / — expect 200 with service, version
echo "--- Test 2: GET / ---"
RESPONSE=$(curl -sw "\n%{http_code}" "${BASE_URL}/" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "GET / status" 200 "$HTTP_CODE" && \
   assert_json_field "GET /" "$BODY" "service" && \
   assert_json_field "GET /" "$BODY" "version"; then
    log_pass "GET / — 200 with correct JSON shape"
fi

# 3. POST /services — expect 200 with id, name, url
echo "--- Test 3: POST /services ---"
RESPONSE=$(curl -sw "\n%{http_code}" -X POST "${BASE_URL}/services" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-service", "url": "https://example.com"}' 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "POST /services status" 200 "$HTTP_CODE" && \
   assert_json_field "POST /services" "$BODY" "id" && \
   assert_json_field "POST /services" "$BODY" "name"; then
    log_pass "POST /services — 200 with correct JSON shape"
fi

# 4. POST /services (duplicate) — expect 409
echo "--- Test 4: POST /services (duplicate) ---"
RESPONSE=$(curl -sw "\n%{http_code}" -X POST "${BASE_URL}/services" \
    -H "Content-Type: application/json" \
    -d '{"name": "test-service", "url": "https://example.com"}' 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)

if assert_status "POST /services duplicate" 409 "$HTTP_CODE"; then
    log_pass "POST /services (duplicate) — 409 Conflict"
fi

# 5. GET /services — expect 200 with array containing our service
echo "--- Test 5: GET /services ---"
RESPONSE=$(curl -sw "\n%{http_code}" "${BASE_URL}/services" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "GET /services status" 200 "$HTTP_CODE"; then
    # Verify it's an array with at least one item containing 'id'
    if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)>0 and 'id' in d[0]" 2>/dev/null; then
        log_pass "GET /services — 200 with correct JSON array"
    else
        log_fail "GET /services" "Response is not a non-empty array with expected fields"
    fi
fi

# 6. POST /incidents — expect 200 with id, status
echo "--- Test 6: POST /incidents ---"
RESPONSE=$(curl -sw "\n%{http_code}" -X POST "${BASE_URL}/incidents" \
    -H "Content-Type: application/json" \
    -d '{"service_name": "test-service", "title": "Test Incident", "description": "Testing", "severity": "minor"}' 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "POST /incidents status" 200 "$HTTP_CODE" && \
   assert_json_field "POST /incidents" "$BODY" "id" && \
   assert_json_field "POST /incidents" "$BODY" "status"; then
    log_pass "POST /incidents — 200 with correct JSON shape"
fi

# 7. GET /incidents — expect 200 with array
echo "--- Test 7: GET /incidents ---"
RESPONSE=$(curl -sw "\n%{http_code}" "${BASE_URL}/incidents" 2>/dev/null)
HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | sed '$d')

if assert_status "GET /incidents status" 200 "$HTTP_CODE"; then
    if echo "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); assert isinstance(d,list) and len(d)>0 and 'id' in d[0]" 2>/dev/null; then
        log_pass "GET /incidents — 200 with correct JSON array"
    else
        log_fail "GET /incidents" "Response is not a non-empty array with expected fields"
    fi
fi

# --- Summary ----------------------------------------------------------------

echo ""
echo "========================================="
echo "  Results: ${PASSED} passed, ${FAILED} failed (${TOTAL} total)"
echo "========================================="
echo ""

if [ "$FAILED" -gt 0 ]; then
    echo -e "${RED}❌ INTEGRATION TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✅ ALL INTEGRATION TESTS PASSED${NC}"
    exit 0
fi
