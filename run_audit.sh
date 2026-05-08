#!/usr/bin/env bash
# =============================================================================
# run_audit.sh — Master Audit Runner
# KubeCounty — DevOps Consulting
#
# Downloads and runs both audit scripts in sequence.
# Output is saved to dated Markdown files on the server.
#
# USAGE:
#   bash run_audit.sh
# =============================================================================

set -euo pipefail

REPO="https://raw.githubusercontent.com/MalchielUrias/devops_auditor/main"
DATE=$(date +%Y%m%d)
HOST=$(hostname)

echo "============================================="
echo " KubeCounty — DevOps Audit Runner"
echo " Host: $HOST"
echo " Date: $DATE"
echo "============================================="
echo ""

# ── Download scripts ──────────────────────────────────────────────────────────

echo "[1/4] Downloading machine_audit.sh..."
curl -fsSL -o machine_audit.sh "$REPO/machine_audit.sh"
echo "      Done."

echo "[2/4] Downloading docker_audit.sh..."
curl -fsSL -o docker_audit.sh "$REPO/docker_audit.sh"
echo "      Done."

# ── Run machine audit ─────────────────────────────────────────────────────────

echo ""
echo "[3/4] Running machine audit — output: machine_audit_${HOST}_${DATE}.md"
echo "      This may take a minute..."
bash machine_audit.sh | tee "machine_audit_${HOST}_${DATE}.md"
echo ""
echo "      Machine audit complete."

# ── Run docker audit ──────────────────────────────────────────────────────────

echo ""
echo "[4/4] Running docker audit — output: docker_audit_${HOST}_${DATE}.md"
echo "      This may take a minute..."
bash docker_audit.sh | tee "docker_audit_${HOST}_${DATE}.md"
echo ""
echo "      Docker audit complete."

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "============================================="
echo " Audit complete. Files saved:"
echo "   machine_audit_${HOST}_${DATE}.md"
echo "   docker_audit_${HOST}_${DATE}.md"
echo "============================================="
