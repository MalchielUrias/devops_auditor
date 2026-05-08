#!/usr/bin/env bash
# =============================================================================
# machine_audit.sh — Read-Only Machine-Level Audit Script
# Malchiel Urias — DevOps Consulting
#
# SAFETY GUARANTEE: This script is strictly read-only.
# It runs no commands that modify, restart, delete, or install anything.
# Safe to run on any live server without prior change approval.
#
# USAGE:
#   bash machine_audit.sh | tee audit_$(hostname)_$(date +%Y%m%d).md
#
# Run on each Droplet individually via the browser console or SSH.
# Output is Markdown — pipe to a file and copy off the server.
# =============================================================================

set -euo pipefail

# ── Helpers ──────────────────────────────────────────────────────────────────

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
DIVIDER="---"

h1()  { echo ""; echo "# $*"; echo "$DIVIDER"; }
h2()  { echo ""; echo "## $*"; }
h3()  { echo ""; echo "### $*"; }
info(){ echo "> $*"; }
cmd() {
  # Runs a command and wraps output in a fenced code block.
  # If the command fails (e.g. tool not found), notes it gracefully.
  local label="$1"; shift
  echo ""
  echo "**\`$label\`**"
  echo '```'
  "$@" 2>&1 || echo "[command returned non-zero or not available]"
  echo '```'
}
warn() { echo ""; echo "> ⚠️  **Note:** $*"; }

# ── Cover ─────────────────────────────────────────────────────────────────────

echo "# Machine-Level Audit — \`$HOSTNAME\`"
echo ""
echo "| Field | Value |"
echo "|-------|-------|"
echo "| Host | \`$HOSTNAME\` |"
echo "| Audit timestamp | $TIMESTAMP |"
echo "| Script version | 1.0 |"
echo "| Scope | Read-only inspection — no changes made |"
echo ""
echo "$DIVIDER"

# =============================================================================
# SECTION 1 — SYSTEM IDENTITY
# =============================================================================
h1 "1. System Identity"

h2 "1.1 OS & Kernel"
cmd "lsb_release -a"          lsb_release -a
cmd "uname -r (kernel)"       uname -r
cmd "uname -a (full)"         uname -a

h2 "1.2 Uptime & Load"
cmd "uptime"                  uptime

h2 "1.3 Hostname & Network Identity"
cmd "hostname"                hostname
cmd "hostname -I (all IPs)"   hostname -I

# =============================================================================
# SECTION 2 — SSH CONFIGURATION
# =============================================================================
h1 "2. SSH Configuration"
info "Checking effective SSH daemon configuration. This is the actual running state, not just the config file."

h2 "2.1 Effective SSH Daemon Settings"
cmd "sshd -T (key auth settings)" \
  bash -c "sshd -T 2>/dev/null | grep -E 'passwordauthentication|permitrootlogin|pubkeyauthentication|permitemptypasswords|usepam|authorizedkeysfile|port '"

h2 "2.2 Raw sshd_config (commented lines excluded)"
cmd "sshd_config (active lines only)" \
  bash -c "grep -vE '^\s*#|^\s*$' /etc/ssh/sshd_config 2>/dev/null || echo '[sshd_config not readable]'"

h2 "2.3 Authorised Keys"
info "Lists all public keys authorised to connect. Each key should have a known, documented owner."
cmd "~/.ssh/authorized_keys" \
  bash -c "if [ -f ~/.ssh/authorized_keys ]; then cat ~/.ssh/authorized_keys; else echo '[authorized_keys not found]'; fi"

h2 "2.4 Private Keys on Server"
info "Private keys should NOT be stored on servers. Any findings here should be flagged."
warn "Searching entire filesystem — may take a moment. Errors from restricted directories are suppressed."
cmd "find: private key files" \
  bash -c "find / -maxdepth 6 \( -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' -o -name '*.pem' -o -name '*.key' \) 2>/dev/null | grep -v '/proc/' | grep -v '/sys/' || echo '[none found]'"

h2 "2.5 Recent Login History"
info "Last 20 logins — review for unexpected source IPs or usernames."
cmd "last -n 20" \
  last -n 20

h2 "2.6 Failed Login Attempts"
info "Recent failed SSH attempts — indicator of brute force activity."
cmd "lastb (failed logins, last 20)" \
  bash -c "lastb -n 20 2>/dev/null || echo '[lastb not available or requires root]'"

# =============================================================================
# SECTION 3 — FIREWALL & NETWORK EXPOSURE
# =============================================================================
h1 "3. Firewall & Network Exposure"

h2 "3.1 OS Firewall (ufw)"
cmd "ufw status verbose" \
  bash -c "ufw status verbose 2>/dev/null || echo '[ufw not available or inactive]'"

h2 "3.2 iptables Rules"
cmd "iptables -L (filter table)" \
  bash -c "iptables -L -n --line-numbers 2>/dev/null || echo '[iptables not readable — may need elevated permissions]'"

h2 "3.3 Listening Ports & Services"
info "Shows all listening TCP ports and the process owning each. Flag anything on 0.0.0.0 (all interfaces) that should only be on 127.0.0.1."
cmd "ss -tlnp (listening TCP)" \
  bash -c "ss -tlnp 2>/dev/null || netstat -tlnp 2>/dev/null || echo '[ss and netstat not available]'"

h2 "3.4 All Open Sockets (including UDP)"
cmd "ss -ulnp (listening UDP)" \
  bash -c "ss -ulnp 2>/dev/null || echo '[not available]'"

h2 "3.5 Network Interfaces"
cmd "ip addr show" \
  bash -c "ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo '[not available]'"

h2 "3.6 Routing Table"
cmd "ip route" \
  bash -c "ip route 2>/dev/null || route -n 2>/dev/null || echo '[not available]'"

# =============================================================================
# SECTION 4 — SYSTEM HYGIENE
# =============================================================================
h1 "4. System Hygiene"

h2 "4.1 Unattended Upgrades"
info "Automatic security patching configuration. Should be enabled on all servers."
cmd "20auto-upgrades config" \
  bash -c "cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null || echo '[file not found — unattended-upgrades may not be configured]'"
cmd "50unattended-upgrades config" \
  bash -c "cat /etc/apt/apt.conf.d/50unattended-upgrades 2>/dev/null | head -40 || echo '[file not found]'"

h2 "4.2 Pending Security Updates"
info "Lists available security updates without installing them."
cmd "apt list --upgradable (security)" \
  bash -c "apt list --upgradable 2>/dev/null | grep -i security | head -30 || echo '[no pending security updates found or apt not available]'"

h2 "4.3 Last apt Update"
cmd "apt history (recent)" \
  bash -c "ls -lt /var/log/apt/ 2>/dev/null | head -10 || echo '[apt log not accessible]'"

h2 "4.4 Cron Jobs"
info "Documents all scheduled tasks. Each should have a known owner and purpose."
h3 "Root crontab"
cmd "crontab -l (root)" \
  bash -c "crontab -l 2>/dev/null || echo '[no root crontab or not readable]'"
h3 "System cron directories"
cmd "ls /etc/cron*" \
  bash -c "ls -la /etc/cron* 2>/dev/null || echo '[not found]'"
cmd "cat /etc/cron.d/*" \
  bash -c "cat /etc/cron.d/* 2>/dev/null || echo '[empty or not found]'"
h3 "All user crontabs"
cmd "user crontabs" \
  bash -c "for user in \$(cut -d: -f1 /etc/passwd); do crontab -u \"\$user\" -l 2>/dev/null && echo \"--- user: \$user\"; done || echo '[none found]'"

h2 "4.5 Systemd Services"
info "Active services running on the server."
cmd "systemctl list-units --type=service --state=running" \
  bash -c "systemctl list-units --type=service --state=running 2>/dev/null | head -40 || echo '[systemctl not available]'"

h2 "4.6 Users & Sudo Access"
info "All user accounts and who has sudo privileges."
cmd "/etc/passwd (non-system users)" \
  bash -c "awk -F: '\$3 >= 1000 {print}' /etc/passwd 2>/dev/null || echo '[not readable]'"
cmd "sudo group members" \
  bash -c "getent group sudo 2>/dev/null || getent group wheel 2>/dev/null || echo '[not readable]'"
cmd "/etc/sudoers.d/" \
  bash -c "ls -la /etc/sudoers.d/ 2>/dev/null && cat /etc/sudoers.d/* 2>/dev/null || echo '[not readable]'"

# =============================================================================
# SECTION 5 — DISK USAGE
# =============================================================================
h1 "5. Disk Usage"

h2 "5.1 Filesystem Overview"
cmd "df -h (all mounts)" \
  df -h

h2 "5.2 Block Devices & Volumes"
cmd "lsblk" \
  bash -c "lsblk 2>/dev/null || echo '[lsblk not available]'"

h2 "5.3 Docker Disk Usage"
info "Breakdown of disk space used by Docker images, containers, and volumes."
cmd "docker system df" \
  bash -c "docker system df 2>/dev/null || echo '[Docker not available or not running]'"

h2 "5.4 Top Disk Consumers — Docker"
cmd "du -sh /var/lib/docker/* (Docker subdirs)" \
  bash -c "timeout 30 du -sh --max-depth=1 /var/lib/docker/ 2>/dev/null | sort -rh | head -20 || echo '[not accessible or timed out]'"

h2 "5.5 Top Disk Consumers — Logs"
cmd "du -sh /var/log/* (log files)" \
  bash -c "du -sh /var/log/* 2>/dev/null | sort -rh | head -20 || echo '[not accessible]'"

h2 "5.6 Docker Log File Sizes"
info "Individual Docker container log files. Large files here indicate log rotation is not configured."
cmd "Docker container log sizes" \
  bash -c "find /var/lib/docker/containers -name '*.log' -exec ls -lh {} \; 2>/dev/null | sort -k5 -rh | head -20 || echo '[not accessible]'"

h2 "5.7 Largest Files on System (top 20)"
warn "This check may take a moment on servers with large disks."
cmd "find / largest files" \
  bash -c "timeout 60 find / -maxdepth 6 -type f -not -path '/proc/*' -not -path '/sys/*' -not -path '/dev/*' -not -path '/var/lib/docker/*' 2>/dev/null | xargs ls -lh 2>/dev/null | sort -k5 -rh | head -20 || echo '[not accessible or timed out]'"

# =============================================================================
# SECTION 6 — DOCKER DAEMON
# =============================================================================
h1 "6. Docker Daemon"

h2 "6.1 Docker Info"
info "Overall Docker daemon configuration including logging driver, storage driver, and security flags."
cmd "docker info" \
  bash -c "docker info 2>/dev/null || echo '[Docker not available or not running]'"

h2 "6.2 Docker Daemon Config File"
cmd "/etc/docker/daemon.json" \
  bash -c "cat /etc/docker/daemon.json 2>/dev/null || echo '[daemon.json not found — Docker using default config]'"

h2 "6.3 Docker Version"
cmd "docker version" \
  bash -c "docker version 2>/dev/null || echo '[not available]'"

# =============================================================================
# SECTION 7 — ENVIRONMENT SUMMARY FLAGS
# =============================================================================
h1 "7. Automated Finding Flags"
info "These are automated checks that flag likely issues. Verify each manually before including in the report."
echo ""

echo "| Check | Result |"
echo "|-------|--------|"

# SSH: PermitRootLogin
ROOT_LOGIN=$(sshd -T 2>/dev/null | grep -i 'permitrootlogin' | awk '{print $2}' || echo "unknown")
if [ "$ROOT_LOGIN" = "yes" ]; then
  echo "| PermitRootLogin | ⚠️  YES — root SSH login enabled (High severity) |"
else
  echo "| PermitRootLogin | ✅  $ROOT_LOGIN |"
fi

# SSH: PasswordAuthentication
PASS_AUTH=$(sshd -T 2>/dev/null | grep -i 'passwordauthentication' | awk '{print $2}' || echo "unknown")
if [ "$PASS_AUTH" = "yes" ]; then
  echo "| PasswordAuthentication | ⚠️  YES — password auth enabled (High severity) |"
else
  echo "| PasswordAuthentication | ✅  $PASS_AUTH |"
fi

# Unattended upgrades
if cat /etc/apt/apt.conf.d/20auto-upgrades 2>/dev/null | grep -q '"1"'; then
  echo "| Unattended upgrades | ✅  Appears configured |"
else
  echo "| Unattended upgrades | ⚠️  Not configured or not confirmed (Medium severity) |"
fi

# UFW
UFW_STATUS=$(ufw status 2>/dev/null | head -1 || echo "unknown")
if echo "$UFW_STATUS" | grep -qi "active"; then
  echo "| UFW firewall | ✅  Active |"
else
  echo "| UFW firewall | ⚠️  Inactive or not installed (Medium severity) |"
fi

# Disk usage root partition
ROOT_USAGE=$(df / | awk 'NR==2 {print $5}' | tr -d '%')
if [ "$ROOT_USAGE" -ge 85 ] 2>/dev/null; then
  echo "| Root disk usage | ⚠️  ${ROOT_USAGE}% — high (High severity if above 90%) |"
else
  echo "| Root disk usage | ✅  ${ROOT_USAGE}% |"
fi

# Docker socket exposure
SOCK_EXPOSURE=0
if docker ps -q 2>/dev/null | grep -q . 2>/dev/null; then
  SOCK_EXPOSURE=$(docker inspect $(docker ps -q 2>/dev/null) 2>/dev/null | { grep "docker.sock" || true; } | wc -l | tr -d ' ') || SOCK_EXPOSURE=0
fi
if [ "${SOCK_EXPOSURE:-0}" -gt 0 ]; then
  echo "| Docker socket mounted in container | ⚠️  YES — $SOCK_EXPOSURE container(s) (Critical severity) |"
else
  echo "| Docker socket mounted in container | ✅  Not detected |"
fi

# Private keys on server
PRIV_KEYS=0
PRIV_KEYS=$(find / -maxdepth 6 \( -name 'id_rsa' -o -name 'id_ed25519' -o -name '*.pem' \) 2>/dev/null \
  | { grep -v '/proc/' || true; } \
  | { grep -v '/sys/' || true; } \
  | wc -l \
  | tr -d ' ')
if [ "${PRIV_KEYS:-0}" -gt 0 ]; then
  echo "| Private keys on server | ⚠️  $PRIV_KEYS file(s) found (High severity) |"
else
  echo "| Private keys on server | ✅  None found |"
fi

# =============================================================================
# FOOTER
# =============================================================================
echo ""
echo "$DIVIDER"
echo ""
echo "_Audit completed: ${TIMESTAMP}_"
echo ""
echo "_This output was generated by a read-only script. No changes were made to this server._"
echo ""
echo "_KubeCounty — DevOps Consulting_"
