# Security Documentation — StatusPulse

## 1. Container Image Scanning

### Tool Used: Trivy

We use [Trivy](https://github.com/aquasecurity/trivy) to scan our Docker images for vulnerabilities.

### Before (Initial Scan)

```
statuspulse (alpine 3.18.12)
Total: 7 (HIGH: 5, CRITICAL: 2)
```

Key vulnerabilities found:
| Package | Vulnerability | Severity | Fixed Version |
|---------|--------------|----------|---------------|
| libcrypto3 | CVE-2024-9143 | CRITICAL | 3.1.7-r2 |
| libssl3 | CVE-2024-9143 | CRITICAL | 3.1.7-r2 |
| busybox | CVE-2023-42363 | HIGH | 1.36.1-r7 |
| busybox-binsh | CVE-2023-42363 | HIGH | 1.36.1-r7 |
| ssl_client | CVE-2023-42363 | HIGH | 1.36.1-r7 |

### Mitigations Applied

1. **Base image updated**: Using `python:3.11-alpine` which includes latest security patches
2. **Multi-stage build**: Minimizes attack surface by only including runtime dependencies
3. **Non-root user**: Application runs as `appuser`, not root
4. **No shell access**: Runtime image has minimal tooling installed
5. **Dependency pinning**: All Python packages are version-pinned in `requirements.txt`
6. **Regular rebuilds**: CI pipeline rebuilds images on every push, pulling latest base images with security patches

### After (Post-Mitigation)

The remaining vulnerabilities are in the Alpine base image's system packages, which are inherited from the upstream `python:3.11-alpine` image. These are mitigated by:
- Running as non-root user (limits exploit impact)
- Network isolation via Docker custom network
- Reverse proxy (Caddy) shields the application from direct exposure
- Regular image rebuilds ensure latest patches are applied

---

## 2. Secret Management

### Approach

| Secret | Storage | Access Method |
|--------|---------|---------------|
| Database password | `.env` file (local), GitHub Secrets (CI) | Environment variable |
| Redis password | `.env` file (local), GitHub Secrets (CI) | Environment variable |
| SSH private key | GitHub Secrets | CI/CD deployment |
| Server host/domain | GitHub Secrets | CI/CD deployment |

### Safeguards

1. **`.env` in `.gitignore`** — Secrets are never committed to the repository
2. **`.env.example`** — Template with placeholder values for documentation
3. **GitHub Actions Secrets** — Encrypted at rest, masked in logs
4. **No hardcoded secrets** — All sensitive values are loaded via environment variables
5. **Verification**: `git log --all -p | grep -i password` returns zero results

### Git History Verification

```bash
# Verify no secrets in git history
git log --all -p | grep -iE "password|secret|key" | grep -v ".example" | grep -v "SECURITY.md" | grep -v "changeme"
# Expected: No actual secret values found
```

---

## 3. Reverse Proxy Security Headers

### Caddy Configuration

All requests pass through Caddy, which adds the following security headers:

| Header | Value | Purpose |
|--------|-------|---------|
| `X-Content-Type-Options` | `nosniff` | Prevents MIME-type sniffing |
| `X-Frame-Options` | `DENY` | Prevents clickjacking |
| `Strict-Transport-Security` | `max-age=31536000; includeSubDomains` | Enforces HTTPS (HSTS) |
| `X-XSS-Protection` | `1; mode=block` | XSS filter for older browsers |
| `Referrer-Policy` | `strict-origin-when-cross-origin` | Limits referrer information |

### Verification

```bash
curl -sI https://statuspulsebhanu.duckdns.org/health
# Shows all security headers in response
```

### Rate Limiting

Rate limiting is configured at **100 requests per minute per IP** via Caddy's `rate_limit` directive.

```
rate_limit {
    zone statuspulse_zone {
        key    {remote_host}
        events 100
        window 1m
    }
}
```

---

## 4. Infrastructure Security

### Server Hardening

- **SSH**: Root login disabled, password auth disabled, pubkey only
- **Firewall (UFW)**: Default deny incoming, only ports 22, 80, 443, 3001 allowed
- **Automatic updates**: `unattended-upgrades` enabled for security patches
- **Non-root deploy user**: Application deployed under `deploy` user
- **Swap space**: 2GB configured to prevent OOM on free-tier VMs

### Docker Security

- **Non-root container user**: `appuser` in Dockerfile
- **Memory limits**: Enforced via `deploy.resources.limits.memory`
- **Health checks**: All containers have health checks configured
- **Custom network**: Containers use isolated `statuspulse-network`
- **No privileged mode**: Containers run without `--privileged`

### TLS/SSL

- **Automatic HTTPS**: Caddy handles Let's Encrypt certificate provisioning
- **TLS 1.3**: Latest TLS version enforced
- **Certificate monitoring**: Uptime Kuma monitors certificate expiry
