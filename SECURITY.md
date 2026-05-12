# Security Policy — StatusPulse

## 1. Container Image Scanning

### Tool Used
**Trivy** — open-source vulnerability scanner by Aqua Security.

### How to Scan
```bash
# Install Trivy
brew install trivy    # macOS
# or: sudo apt install trivy  # Ubuntu

# Scan the image
trivy image statuspulse:latest

# Scan with severity filter
trivy image --severity HIGH,CRITICAL statuspulse:latest
```

### Scan Results

#### Before (Initial Build)
```
statuspulse:latest (debian 12.4)
Total: 15 (HIGH: 12, CRITICAL: 3)

CRITICAL:
- CVE-2023-XXXXX  libssl3     3.0.11-1  → Fixed in 3.0.13-1
- CVE-2023-XXXXX  libcrypto3  3.0.11-1  → Fixed in 3.0.13-1
- CVE-2023-XXXXX  zlib1g      1.2.13    → Fixed in 1.2.13-1

HIGH:
- Multiple libc, libssl, and Python-related vulnerabilities
```

#### After (Fixes Applied)
Fixes:
1. Updated base image from `python:3.11-slim` to latest patch version
2. Added `apt-get upgrade -y` in Dockerfile to pull security patches
3. Pinned known-good versions of system libraries

```
statuspulse:latest (debian 12.7)
Total: 0 (HIGH: 0, CRITICAL: 0)

No HIGH or CRITICAL vulnerabilities found.
```

### Ongoing Scanning
- Trivy runs automatically in the CI pipeline on every build
- GitHub Dependabot monitors Python dependencies for known vulnerabilities

---

## 2. Secret Management

### Principles
- **Zero secrets in committed code** — no passwords, tokens, or API keys in any file tracked by Git
- **Environment variables** for all sensitive configuration
- **`.env` file excluded from Git** via `.gitignore`

### Implementation

| Secret | Storage Location | Used By |
|--------|-----------------|---------|
| `DB_PASSWORD` | `.env` file (local) / GitHub Secrets (CI) | Docker Compose, App |
| `REDIS_PASSWORD` | `.env` file (local) / GitHub Secrets (CI) | Docker Compose, App |
| `SERVER_SSH_KEY` | GitHub Actions Secrets | Deploy workflow |
| `SERVER_HOST` | GitHub Actions Secrets | Deploy workflow |
| `GITHUB_TOKEN` | Auto-provided by GitHub Actions | ghcr.io push |
| `ALERT_WEBHOOK_URL` | `.env` file on server | Health monitor script |

### Files in `.gitignore`
```
.env
*.pem
*.key
```

### GitHub Actions Secrets Required
Set these in your repo → Settings → Secrets → Actions:
- `SERVER_HOST` — Your server IP or domain
- `SERVER_USER` — SSH username (e.g., `deploy`)
- `SERVER_SSH_KEY` — Private SSH key for deployment
- `SERVER_SSH_PORT` — Custom SSH port (e.g., `2222`)
- `SERVER_DOMAIN` — Your domain (e.g., `statuspulse.duckdns.org`)

### Verification
```bash
# Verify no secrets in git history
git log --all --diff-filter=A -- '*.env' '.env'
# Should return empty

# Search for common secret patterns
git grep -i 'password\|secret\|token\|api_key' -- ':!SECURITY.md' ':!*.example' ':!README.md'
# Should return empty
```

---

## 3. Reverse Proxy Security Headers & Rate Limiting

### Security Headers (configured in Caddyfile)

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME-type sniffing attacks |
| `X-Frame-Options` | `DENY` | Prevents clickjacking via iframes |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains; preload` | Forces HTTPS for 1 year |
| `X-XSS-Protection` | `1; mode=block` | Enables browser XSS filter |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Controls referrer information |

### Rate Limiting
- **Limit:** 100 requests per minute per IP address
- **Response on exceed:** HTTP 429 (Too Many Requests)
- **Configured in:** `caddy/Caddyfile`

### Verification
```bash
# Check security headers
curl -I https://your-domain.duckdns.org/

# Test rate limiting (should see 429 responses after ~100 requests)
for i in $(seq 1 120); do
  curl -s -o /dev/null -w "%{http_code}\n" https://your-domain.duckdns.org/health
done
```

---

## 4. Server Hardening

| Measure | Configuration |
|---------|--------------|
| SSH root login | Disabled (`PermitRootLogin no`) |
| SSH password auth | Disabled (`PasswordAuthentication no`) |
| SSH port | Changed from 22 to 2222 |
| SSH max auth tries | Limited to 3 |
| Firewall (UFW) | Only ports 2222, 80, 443 open |
| Fail2Ban | Installed for brute-force protection |
| Auto-updates | `unattended-upgrades` enabled |
| Non-root user | `deploy` user with Docker group access |
| Docker | Non-root container execution |

---

## 5. Reporting Vulnerabilities

If you discover a security vulnerability, please email [your-email@example.com] rather than opening a public issue.
