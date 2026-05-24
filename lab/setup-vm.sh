#!/usr/bin/env bash
# Provision a fresh Debian/Ubuntu VM as an ansnet test environment.
#
# Installs every dependency the project's test layers need (docs/testing.md):
#   - Docker             container runtime for Containerlab and Molecule
#   - Containerlab       boots the lab topology (lab/topology.clab.yml)
#   - Python virtualenv  ansible-core, ansible-lint, molecule, testinfra,
#                        pre-commit etc., pinned by ansible/requirements.txt
#   - Ansible Galaxy collections from ansible/requirements.yml
#   - pre-commit git hooks
#   - the lab container images, pre-pulled
#
# When it finishes the VM can lint, run `molecule test`, deploy the
# Containerlab lab (./lab/deploy.sh up) and run `pytest tests/`.
#
# Usage:
#   ./lab/setup-vm.sh                 install everything (idempotent)
#   ./lab/setup-vm.sh --skip-images   skip pre-pulling the lab images
#   ./lab/setup-vm.sh --help
#
# Targets Debian/Ubuntu (apt). Run as a normal user with sudo rights — the
# script elevates only for apt, Docker and Containerlab; the virtualenv is
# created as the calling user so it is not left root-owned.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${REPO_ROOT}/.venv"
SKIP_IMAGES=0
DOCKER_GROUP_ADDED=0
SUDO=()

# Lab container images — keep in sync with lab/topology.clab.yml.
LAB_IMAGES=(
  "ghcr.io/nokia/srlinux:latest"
  "quay.io/frrouting/frr:latest"
  "ghcr.io/hellt/network-multitool:latest"
)

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
err()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; }

trap 'err "Setup failed (line ${LINENO}). Fix the cause and re-run — the script is idempotent."' ERR

usage() {
  cat <<'EOF'
Usage: ./lab/setup-vm.sh [--skip-images] [--help]

Provisions a Debian/Ubuntu VM as an ansnet test environment: Docker,
Containerlab, a Python virtualenv from ansible/requirements.txt, the Galaxy
collections, pre-commit hooks and the lab container images.

  --skip-images   do not pre-pull the Containerlab images
  -h, --help      show this help
EOF
}

# --- argument parsing --------------------------------------------------------
for arg in "$@"; do
  case "${arg}" in
    --skip-images) SKIP_IMAGES=1 ;;
    -h|--help)     usage; exit 0 ;;
    *) err "Unknown argument: ${arg}"; usage >&2; exit 2 ;;
  esac
done

# --- preflight ---------------------------------------------------------------
preflight() {
  if [ ! -f "${REPO_ROOT}/ansible/requirements.txt" ]; then
    err "Cannot find ansible/requirements.txt — run this from inside the repo."
    exit 1
  fi

  # shellcheck disable=SC1091
  . /etc/os-release 2>/dev/null || true
  local id="${ID:-unknown}" like="${ID_LIKE:-}"
  if [ "${id}" != "debian" ] && [ "${id}" != "ubuntu" ] && [[ "${like}" != *debian* ]]; then
    err "This script targets Debian/Ubuntu (apt). Detected: ${id}."
    err "On another distro install the equivalents of docker, containerlab and"
    err "python3-venv, then: pip install -r ansible/requirements.txt"
    exit 1
  fi

  if [ "$(id -u)" -eq 0 ]; then
    SUDO=()
  elif command -v sudo >/dev/null 2>&1; then
    SUDO=(sudo)
    log "Validating sudo access (you may be prompted for your password)"
    sudo -v
  else
    err "Need root or sudo to install system packages."
    exit 1
  fi
}

# --- steps -------------------------------------------------------------------
install_apt_packages() {
  log "Installing base apt packages"
  export DEBIAN_FRONTEND=noninteractive
  "${SUDO[@]}" apt-get update -qq
  "${SUDO[@]}" apt-get install -y -qq \
    ca-certificates curl git python3 python3-venv python3-pip shellcheck
}

install_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already present — $(docker --version)"
  else
    log "Installing Docker via get.docker.com"
    curl -fsSL https://get.docker.com | "${SUDO[@]}" sh
  fi
  "${SUDO[@]}" systemctl enable --now docker >/dev/null 2>&1 || true

  local user; user="$(id -un)"
  if [ "${user}" != "root" ] && ! id -nG "${user}" | tr ' ' '\n' | grep -qx docker; then
    log "Adding ${user} to the docker group"
    "${SUDO[@]}" usermod -aG docker "${user}"
    DOCKER_GROUP_ADDED=1
  fi
}

install_containerlab() {
  if command -v containerlab >/dev/null 2>&1; then
    log "Containerlab already present — $(command -v containerlab)"
  else
    log "Installing Containerlab via get.containerlab.dev"
    curl -sL https://get.containerlab.dev | "${SUDO[@]}" bash
  fi
}

setup_venv() {
  if [ -d "${VENV_DIR}" ]; then
    log "Reusing existing virtualenv at ${VENV_DIR}"
  else
    log "Creating Python virtualenv at ${VENV_DIR}"
    python3 -m venv "${VENV_DIR}"
  fi
  log "Installing Python tooling from ansible/requirements.txt (pins ansible-core <2.18)"
  "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
  "${VENV_DIR}/bin/pip" install --quiet -r "${REPO_ROOT}/ansible/requirements.txt"
}

install_collections() {
  log "Installing Ansible collections from ansible/requirements.yml"
  ( cd "${REPO_ROOT}" \
      && "${VENV_DIR}/bin/ansible-galaxy" collection install -r ansible/requirements.yml )
}

setup_precommit() {
  if [ -f "${REPO_ROOT}/.pre-commit-config.yaml" ]; then
    log "Installing pre-commit git hooks"
    ( cd "${REPO_ROOT}" && "${VENV_DIR}/bin/pre-commit" install )
  fi
}

pull_lab_images() {
  if [ "${SKIP_IMAGES}" -eq 1 ]; then
    log "Skipping lab image pre-pull (--skip-images)"
    return 0
  fi
  log "Pre-pulling lab container images"
  local img
  for img in "${LAB_IMAGES[@]}"; do
    if "${SUDO[@]}" docker pull "${img}" >/dev/null 2>&1; then
      log "  pulled ${img}"
    else
      warn "  could not pull ${img} — deploy.sh will retry on first 'up'"
    fi
  done
}

summary() {
  log "----------------------------------------------------------------"
  log "Test environment ready."
  log "  Docker        $(docker --version 2>/dev/null || echo 'not detected')"
  log "  Containerlab  $(command -v containerlab || echo 'not detected')"
  log "  Virtualenv    ${VENV_DIR}"
  log "  Ansible       $("${VENV_DIR}/bin/ansible" --version 2>/dev/null | head -n1 || echo '?')"
  log ""
  log "Next steps:"
  log "  source .venv/bin/activate          # enter the environment"
  log "  yamllint . && ansible-lint         # layer 1 — static checks"
  log "  cd ansible/roles/<role> && molecule test   # layer 3 — per role"
  log "  ./lab/deploy.sh up                 # layer 4 — Containerlab lab"
  log "  pytest tests/testinfra/            # post-deploy state checks"
  if [ "${DOCKER_GROUP_ADDED}" -eq 1 ]; then
    warn ""
    warn "You were added to the 'docker' group. Log out and back in (or run"
    warn "'newgrp docker') before running molecule or docker without sudo."
  fi
  log "----------------------------------------------------------------"
}

main() {
  preflight
  install_apt_packages
  install_docker
  install_containerlab
  setup_venv
  install_collections
  setup_precommit
  pull_lab_images
  summary
}

main "$@"
