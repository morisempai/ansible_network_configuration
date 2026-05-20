#!/usr/bin/env bash
# Deploy or destroy the ansnet Containerlab test topology.
#
# Usage:
#   ./lab/deploy.sh up        deploy the lab (installs Containerlab if missing)
#   ./lab/deploy.sh down      destroy the lab and clean up
#   ./lab/deploy.sh status    show node status
#
# Designed to run both locally (Linux/WSL) and on GitHub-hosted runners.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOPOLOGY="${SCRIPT_DIR}/topology.clab.yml"
ACTION="${1:-up}"

log() { printf '\033[1;34m[lab]\033[0m %s\n' "$*"; }
err() { printf '\033[1;31m[lab]\033[0m %s\n' "$*" >&2; }

ensure_containerlab() {
  if ! command -v containerlab >/dev/null 2>&1; then
    log "Containerlab not found — installing"
    bash -c "$(curl -sL https://get.containerlab.dev)"
  fi
  log "Containerlab $(containerlab version 2>/dev/null | awk '/version/{print $2; exit}')"
}

ensure_docker() {
  if ! docker info >/dev/null 2>&1; then
    err "Docker is not available. Install Docker or run inside a runner that has it."
    exit 1
  fi
}

case "${ACTION}" in
  up)
    ensure_docker
    ensure_containerlab
    log "Deploying topology: ${TOPOLOGY}"
    sudo containerlab deploy --topo "${TOPOLOGY}" --reconfigure
    log "Lab is up. Inventory: ansible/inventory/lab/hosts.yml"
    ;;
  down)
    ensure_containerlab
    log "Destroying topology: ${TOPOLOGY}"
    sudo containerlab destroy --topo "${TOPOLOGY}" --cleanup
    log "Lab is down."
    ;;
  status)
    ensure_containerlab
    sudo containerlab inspect --topo "${TOPOLOGY}"
    ;;
  *)
    err "Unknown action: ${ACTION}"
    err "Usage: $0 {up|down|status}"
    exit 2
    ;;
esac
