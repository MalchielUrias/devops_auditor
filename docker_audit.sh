#!/usr/bin/env bash
# =============================================================================
# docker_audit.sh — Read-Only Docker & Container Audit Script
# KubeCounty — DevOps Consulting
#
# SAFETY GUARANTEE: This script is strictly read-only.
# It runs no commands that modify, restart, delete, or install anything.
# Safe to run on any live server without prior change approval.
#
# USAGE:
#   bash docker_audit.sh | tee docker_audit_$(hostname)_$(date +%Y%m%d).md
#
# Run on each Droplet individually via the browser console or SSH.
# Output is Markdown — pipe to a file and copy off the server.
# =============================================================================

set -euo pipefail

HOSTNAME=$(hostname)
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S %Z')
DIVIDER="---"

h1()  { echo ""; echo "# $*"; echo "$DIVIDER"; }
h2()  { echo ""; echo "## $*"; }
h3()  { echo ""; echo "### $*"; }
info(){ echo "> $*"; }
warn(){ echo ""; echo "> ⚠️  **Note:** $*"; }

cmd() {
  local label="$1"; shift
  echo ""
  echo "**\`$label\`**"
  echo '```'
  "$@" 2>&1 || echo "[command returned non-zero or not available]"
  echo '```'
}

# Check Docker is available before proceeding
if ! command -v docker &>/dev/null; then
  echo "# Docker Audit — \`$HOSTNAME\`"
  echo ""
  echo "> ❌ Docker is not installed or not in PATH on this server. Nothing to audit."
  exit 0
fi

if ! docker info &>/dev/null; then
  echo "# Docker Audit — \`$HOSTNAME\`"
  echo ""
  echo "> ❌ Docker daemon is not running or current user cannot access it."
  exit 0
fi

# ── Cover ─────────────────────────────────────────────────────────────────────

echo "# Docker & Container Audit — \`$HOSTNAME\`"
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
# SECTION 1 — CONTAINER INVENTORY
# =============================================================================
h1 "1. Container Inventory"

h2 "1.1 All Containers (running and stopped)"
info "Full inventory including stopped and crashed containers."
cmd "docker ps -a" \
  docker ps -a

h2 "1.2 Running Containers Only"
cmd "docker ps (running)" \
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}\t{{.RunningFor}}"

h2 "1.3 Exited / Crashed Containers"
info "Any containers in exited state represent services that have failed and not recovered."
cmd "docker ps --filter status=exited" \
  docker ps -a --filter status=exited

h2 "1.4 Restarting Containers"
info "Containers in a restart loop — actively failing."
cmd "docker ps --filter status=restarting" \
  docker ps -a --filter status=restarting

h2 "1.5 Point-in-Time Resource Usage"
info "Snapshot of CPU and memory usage per container. High memory % with no limit set is a risk."
cmd "docker stats --no-stream" \
  docker stats --no-stream

# =============================================================================
# SECTION 2 — RESOURCE LIMITS
# =============================================================================
h1 "2. Resource Limits"
info "Every container should have explicit memory and CPU limits set. Without them, a single runaway container can exhaust all server resources."

h2 "2.1 Memory Limits Per Container"
echo ""
echo "| Container | Memory Limit | Memory Reservation |"
echo "|-----------|-------------|-------------------|"
for id in $(docker ps -q); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  mem_limit=$(docker inspect --format '{{.HostConfig.Memory}}' "$id")
  mem_res=$(docker inspect --format '{{.HostConfig.MemoryReservation}}' "$id")
  if [ "$mem_limit" = "0" ]; then
    echo "| \`$name\` | ⚠️  No limit set | $mem_res |"
  else
    mem_mb=$(echo "$mem_limit / 1048576" | bc 2>/dev/null || echo "$mem_limit bytes")
    echo "| \`$name\` | ✅  ${mem_mb} MiB | $mem_res |"
  fi
done

h2 "2.2 CPU Limits Per Container"
echo ""
echo "| Container | CPU Quota | CPU Period | CPU Shares |"
echo "|-----------|-----------|------------|------------|"
for id in $(docker ps -q); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  cpu_quota=$(docker inspect --format '{{.HostConfig.CpuQuota}}' "$id")
  cpu_period=$(docker inspect --format '{{.HostConfig.CpuPeriod}}' "$id")
  cpu_shares=$(docker inspect --format '{{.HostConfig.CpuShares}}' "$id")
  if [ "$cpu_quota" = "0" ]; then
    echo "| \`$name\` | ⚠️  No quota | $cpu_period | $cpu_shares |"
  else
    echo "| \`$name\` | ✅  $cpu_quota | $cpu_period | $cpu_shares |"
  fi
done

h2 "2.3 Restart Policies Per Container"
echo ""
echo "| Container | Restart Policy | Max Retries |"
echo "|-----------|---------------|-------------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$id")
  retries=$(docker inspect --format '{{.HostConfig.RestartPolicy.MaximumRetryCount}}' "$id")
  if [ "$policy" = "no" ] || [ -z "$policy" ]; then
    echo "| \`$name\` | ⚠️  none — will not recover on reboot | $retries |"
  else
    echo "| \`$name\` | ✅  $policy | $retries |"
  fi
done

# =============================================================================
# SECTION 3 — SECRETS & CONFIGURATION
# =============================================================================
h1 "3. Secrets & Configuration"

h2 "3.1 Environment Variables Per Container"
info "Reviewing environment variables for hardcoded secrets, tokens, passwords, or API keys."
warn "Output may contain sensitive values. Handle this section of the report with care."
echo ""
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  echo "### \`$name\`"
  echo '```'
  docker inspect --format '{{range .Config.Env}}{{println .}}{{end}}' "$id" 2>/dev/null || echo "[not readable]"
  echo '```'
done

h2 "3.2 Docker Socket Exposure"
info "If /var/run/docker.sock is mounted in any container, that container has effective root access to the host."
echo ""
echo "| Container | Docker Socket Mounted |"
echo "|-----------|----------------------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  sock=$(docker inspect "$id" 2>/dev/null | grep -c "docker.sock" || echo "0")
  if [ "$sock" -gt 0 ]; then
    echo "| \`$name\` | ⚠️  YES — docker.sock mounted (Critical severity) |"
  else
    echo "| \`$name\` | ✅  No |"
  fi
done

h2 "3.3 Container User (root check)"
info "Containers running as root inside the container are a higher security risk on escape."
echo ""
echo "| Container | Running As |"
echo "|-----------|-----------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  user=$(docker inspect --format '{{.Config.User}}' "$id")
  if [ -z "$user" ] || [ "$user" = "root" ] || [ "$user" = "0" ]; then
    echo "| \`$name\` | ⚠️  root (or unset — defaults to root) |"
  else
    echo "| \`$name\` | ✅  $user |"
  fi
done

h2 "3.4 Privileged Containers"
info "Privileged containers have full access to the host kernel — equivalent to running as root on the host."
echo ""
echo "| Container | Privileged |"
echo "|-----------|-----------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$id")
  if [ "$priv" = "true" ]; then
    echo "| \`$name\` | ⚠️  YES — privileged mode (Critical severity) |"
  else
    echo "| \`$name\` | ✅  No |"
  fi
done

# =============================================================================
# SECTION 4 — NETWORK SEGMENTATION
# =============================================================================
h1 "4. Network Segmentation"

h2 "4.1 Docker Networks"
cmd "docker network ls" \
  docker network ls

h2 "4.2 Network Details & Connected Containers"
info "Shows which containers are connected to each network. Databases and caches should be on isolated networks."
for net in $(docker network ls --format '{{.Name}}' 2>/dev/null); do
  echo ""
  echo "### Network: \`$net\`"
  echo '```'
  docker network inspect "$net" \
    --format 'Driver: {{.Driver}}
Scope: {{.Scope}}
Containers:{{range $id, $c := .Containers}}
  - {{$c.Name}} ({{$c.IPv4Address}}){{end}}' 2>/dev/null || echo "[not readable]"
  echo '```'
done

h2 "4.3 Port Bindings (host-exposed ports)"
info "Ports bound to 0.0.0.0 on the host are reachable from the public internet. Only necessary ports should be exposed."
echo ""
echo "| Container | Port Bindings |"
echo "|-----------|--------------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  ports=$(docker inspect --format '{{range $p, $b := .HostConfig.PortBindings}}{{$p}}->{{range $b}}{{.HostIp}}:{{.HostPort}} {{end}}{{end}}' "$id" 2>/dev/null)
  if [ -z "$ports" ]; then
    echo "| \`$name\` | No host ports exposed |"
  else
    echo "| \`$name\` | \`$ports\` |"
  fi
done

# =============================================================================
# SECTION 5 — STATEFUL VOLUMES
# =============================================================================
h1 "5. Stateful Volumes"

h2 "5.1 All Docker Volumes"
cmd "docker volume ls" \
  docker volume ls

h2 "5.2 Volume Mounts Per Container"
info "Stateful containers (databases, caches, search engines) must have persistent volumes. Data in containers without volume mounts is lost on container recreation."
echo ""
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  echo "### \`$name\`"
  echo '```'
  docker inspect --format \
    '{{range .Mounts}}Type: {{.Type}} | Source: {{.Source}} | Destination: {{.Destination}} | RW: {{.RW}}
{{end}}' "$id" 2>/dev/null || echo "[no mounts or not readable]"
  echo '```'
done

h2 "5.3 Dangling Volumes (not attached to any container)"
info "Orphaned volumes consume disk space and may contain stale data."
cmd "docker volume ls --filter dangling=true" \
  docker volume ls --filter dangling=true

# =============================================================================
# SECTION 6 — IMAGE AUDIT
# =============================================================================
h1 "6. Image Audit"

h2 "6.1 All Local Images"
cmd "docker images" \
  docker images

h2 "6.2 Image Sizes (largest first)"
cmd "docker images sorted by size" \
  bash -c "docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}\t{{.CreatedSince}}' | sort -rh | head -30"

h2 "6.3 Dangling Images (untagged)"
info "Untagged images serve no deployment purpose and consume registry and local disk space."
cmd "docker images --filter dangling=true" \
  docker images --filter dangling=true

h2 "6.4 Image Age — Oldest Images"
info "Very old images may indicate services that have not been updated or redeployed in a long time."
cmd "docker images sorted by age (oldest first)" \
  bash -c "docker images --format '{{.CreatedAt}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' | sort | head -20"

# =============================================================================
# SECTION 7 — LOGGING CONFIGURATION
# =============================================================================
h1 "7. Logging Configuration"

h2 "7.1 Docker Daemon Logging Driver"
cmd "docker info logging driver" \
  bash -c "docker info 2>/dev/null | grep -i 'logging driver'"

h2 "7.2 Log Driver Per Container"
echo ""
echo "| Container | Log Driver | Log Options |"
echo "|-----------|-----------|-------------|"
for id in $(docker ps -q 2>/dev/null); do
  name=$(docker inspect --format '{{.Name}}' "$id" | tr -d '/')
  driver=$(docker inspect --format '{{.HostConfig.LogConfig.Type}}' "$id")
  opts=$(docker inspect --format '{{.HostConfig.LogConfig.Config}}' "$id")
  echo "| \`$name\` | $driver | $opts |"
done

h2 "7.3 Docker Log Rotation Config"
info "Without log rotation, container logs grow unboundedly and can fill the disk."
cmd "daemon.json log config" \
  bash -c "cat /etc/docker/daemon.json 2>/dev/null | grep -A5 'log' || echo '[daemon.json not found or no log config set]'"

h2 "7.4 Current Container Log File Sizes"
info "Large log files indicate log rotation is not working."
cmd "Docker log file sizes" \
  bash -c "find /var/lib/docker/containers -name '*.log' 2>/dev/null | xargs ls -lh 2>/dev/null | sort -k5 -rh | head -20 || echo '[not accessible]'"

# =============================================================================
# SECTION 8 — AUTOMATED FINDING FLAGS
# =============================================================================
h1 "8. Automated Finding Flags"
info "Auto-detected issues. Verify each manually before including in the report."
echo ""

echo "| Check | Result |"
echo "|-------|--------|"

# Containers with no memory limit
NO_MEM_LIMIT=0
for id in $(docker ps -q 2>/dev/null); do
  limit=$(docker inspect --format '{{.HostConfig.Memory}}' "$id" 2>/dev/null)
  [ "$limit" = "0" ] && NO_MEM_LIMIT=$((NO_MEM_LIMIT + 1))
done
if [ "$NO_MEM_LIMIT" -gt 0 ]; then
  echo "| Containers without memory limits | ⚠️  $NO_MEM_LIMIT container(s) — High severity |"
else
  echo "| Containers without memory limits | ✅  All containers have memory limits |"
fi

# Containers with no CPU limit
NO_CPU_LIMIT=0
for id in $(docker ps -q 2>/dev/null); do
  quota=$(docker inspect --format '{{.HostConfig.CpuQuota}}' "$id" 2>/dev/null)
  [ "$quota" = "0" ] && NO_CPU_LIMIT=$((NO_CPU_LIMIT + 1))
done
if [ "$NO_CPU_LIMIT" -gt 0 ]; then
  echo "| Containers without CPU limits | ⚠️  $NO_CPU_LIMIT container(s) — Medium severity |"
else
  echo "| Containers without CPU limits | ✅  All containers have CPU limits |"
fi

# Containers with no restart policy
NO_RESTART=0
for id in $(docker ps -q 2>/dev/null); do
  policy=$(docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' "$id" 2>/dev/null)
  if [ "$policy" = "no" ] || [ -z "$policy" ]; then NO_RESTART=$((NO_RESTART + 1)); fi
done
if [ "$NO_RESTART" -gt 0 ]; then
  echo "| Containers without restart policy | ⚠️  $NO_RESTART container(s) — High severity |"
else
  echo "| Containers without restart policy | ✅  All containers have restart policies |"
fi

# Docker socket mounted
SOCK_COUNT=0
if docker ps -q 2>/dev/null | grep -q .; then
  SOCK_COUNT=$(docker inspect $(docker ps -q) 2>/dev/null | { grep -c "docker.sock" || true; }) || SOCK_COUNT=0
fi
if [ "$SOCK_COUNT" -gt 0 ]; then
  echo "| Docker socket mounted in container | ⚠️  YES — Critical severity |"
else
  echo "| Docker socket mounted in container | ✅  Not detected |"
fi

# Privileged containers
PRIV_COUNT=0
for id in $(docker ps -q 2>/dev/null); do
  priv=$(docker inspect --format '{{.HostConfig.Privileged}}' "$id" 2>/dev/null)
  if [ "$priv" = "true" ]; then PRIV_COUNT=$((PRIV_COUNT + 1)); fi
done
if [ "$PRIV_COUNT" -gt 0 ]; then
  echo "| Privileged containers | ⚠️  $PRIV_COUNT container(s) — Critical severity |"
else
  echo "| Privileged containers | ✅  None detected |"
fi

# Root containers
ROOT_COUNT=0
for id in $(docker ps -q 2>/dev/null); do
  user=$(docker inspect --format '{{.Config.User}}' "$id" 2>/dev/null)
  if [ -z "$user" ] || [ "$user" = "root" ] || [ "$user" = "0" ]; then ROOT_COUNT=$((ROOT_COUNT + 1)); fi
done
if [ "$ROOT_COUNT" -gt 0 ]; then
  echo "| Containers running as root | ⚠️  $ROOT_COUNT container(s) — Medium severity |"
else
  echo "| Containers running as root | ✅  None detected |"
fi

# Exited containers
EXITED=$(docker ps -a --filter status=exited --format '{{.Names}}' 2>/dev/null | wc -l)
if [ "$EXITED" -gt 0 ]; then
  echo "| Exited / crashed containers | ⚠️  $EXITED container(s) — investigate each |"
else
  echo "| Exited / crashed containers | ✅  None |"
fi

# Dangling images
DANGLING=$(docker images --filter dangling=true -q 2>/dev/null | wc -l)
if [ "$DANGLING" -gt 0 ]; then
  echo "| Dangling (untagged) images | ⚠️  $DANGLING image(s) — consuming disk space |"
else
  echo "| Dangling images | ✅  None |"
fi

# Dangling volumes
DANGLING_VOLS=$(docker volume ls --filter dangling=true -q 2>/dev/null | wc -l)
if [ "$DANGLING_VOLS" -gt 0 ]; then
  echo "| Dangling volumes | ⚠️  $DANGLING_VOLS volume(s) — orphaned, consuming disk |"
else
  echo "| Dangling volumes | ✅  None |"
fi

# Containers on default bridge only
BRIDGE_ONLY=0
for id in $(docker ps -q 2>/dev/null); do
  nets=$(docker inspect --format '{{range $k, $v := .NetworkSettings.Networks}}{{$k}} {{end}}' "$id" 2>/dev/null)
  if echo "$nets" | grep -qw "bridge" && [ "$(echo "$nets" | wc -w)" -eq 1 ]; then
    BRIDGE_ONLY=$((BRIDGE_ONLY + 1))
  fi
done
if [ "$BRIDGE_ONLY" -gt 0 ]; then
  echo "| Containers on default bridge only | ⚠️  $BRIDGE_ONLY container(s) — no network segmentation |"
else
  echo "| Containers on default bridge only | ✅  Containers use named networks |"
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
