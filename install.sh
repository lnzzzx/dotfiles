#!/usr/bin/env bash

set -euo pipefail

INFISICAL_DOMAIN="https://eu.infisical.com"
INFISICAL_PROJECT_ID="8cf99689-4102-40a1-b7f2-f28ae9a0f018"
INFISICAL_ENVIRONMENT="environment"
ENVIRONMENT_DIR="${ENVIRONMENT_DIR:-$HOME/.local/share/environment}"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

ensure_apt_base() {
    log "Dependencias base"
    local packages=(curl git qrencode ca-certificates)
    local missing=()
    for package in "${packages[@]}"; do
        dpkg -s "$package" >/dev/null 2>&1 || missing+=("$package")
    done
    if [ ${#missing[@]} -gt 0 ]; then
        sudo apt-get update
        sudo apt-get install -y "${missing[@]}"
    fi
}

ensure_infisical() {
    log "Infisical CLI"
    command -v infisical >/dev/null 2>&1 && return
    curl -1sLf 'https://artifacts-cli.infisical.com/setup.deb.sh' | sudo -E bash
    sudo apt-get install -y infisical
}

infisical_session() {
    log "Login en Infisical"
    # Interactivo (-i) contra la instancia EU. Infisical guarda la sesión y el dominio en su config,
    # así que los 'secrets get' posteriores (aquí y en bootstrap.sh) los heredan.
    infisical login -i --domain="$INFISICAL_DOMAIN" </dev/tty
}

clone_environment() {
    log "Clonando el repo de configuración"
    local github_token
    github_token="$(infisical secrets get GITHUB_PAT --plain --silent --domain="$INFISICAL_DOMAIN" --projectId "$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENVIRONMENT")"
    if [ -d "$ENVIRONMENT_DIR/.git" ]; then
        git -C "$ENVIRONMENT_DIR" pull --ff-only
    else
        git clone "https://oauth2:${github_token}@github.com/lnzzzx/environment.git" "$ENVIRONMENT_DIR"
    fi
}

main() {
    ensure_apt_base
    ensure_infisical
    infisical_session
    clone_environment

    # A partir de aqui el repo de configuracion toma el control: shell, herramientas, secretos, ejes.
    log "Ejecutando el bootstrap del entorno"
    INFISICAL_PROJECT_ID="$INFISICAL_PROJECT_ID" INFISICAL_ENVIRONMENT="$INFISICAL_ENVIRONMENT" ENVIRONMENT_DIR="$ENVIRONMENT_DIR" bash "$ENVIRONMENT_DIR/bootstrap.sh"
}

main "$@"
