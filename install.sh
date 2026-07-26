#!/usr/bin/env bash

set -euo pipefail

INFISICAL_DOMAIN="https://infisical.com"
INFISICAL_PROJECT_ID="8cf99689-4102-40a1-b7f2-f28ae9a0f018"
INFISICAL_ENVIRONMENT="environment"
ENVIRONMENT_DIR="${ENVIRONMENT_DIR:-$HOME/.local/share/environment}"

log() { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }

ensure_apt_base() {
    log "Dependencias base"
    # curl lo exige el instalador de Infisical; el arranque vino por wget pero apt pone curl enseguida.
    local packages=(curl git ca-certificates)
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
    # Headless si se pasan las credenciales de una machine identity (para VPS sin navegador): universal-auth
    # devuelve un token que exportamos para que los 'secrets get' posteriores lo usen.
    if [ -n "${INFISICAL_CLIENT_ID:-}" ] && [ -n "${INFISICAL_CLIENT_SECRET:-}" ]; then
        INFISICAL_TOKEN="$(infisical login --method=universal-auth \
            --client-id="$INFISICAL_CLIENT_ID" --client-secret="$INFISICAL_CLIENT_SECRET" \
            --domain="$INFISICAL_DOMAIN" --plain --silent)"
        export INFISICAL_TOKEN
        return
    fi
    # Si no, login por navegador (SSO GitHub). Requiere navegador en la máquina, o 'ssh -L' que reenvíe
    # el callback_port a tu navegador local. Infisical guarda la sesión; los 'secrets get' la heredan.
    infisical login --domain="$INFISICAL_DOMAIN" </dev/tty
}

clone_environment() {
    log "Clonando el repo de configuración"
    local github_token
    github_token="$(infisical secrets get GITHUB_PAT --plain --silent --projectId "$INFISICAL_PROJECT_ID" --env="$INFISICAL_ENVIRONMENT" --domain="$INFISICAL_DOMAIN")"
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
    # INFISICAL_TOKEN solo existe si el login fue headless (universal-auth); si fue por navegador, la
    # sesión vive en la config de Infisical y bootstrap.sh la hereda sin pasarla. El :- evita el unbound.
    INFISICAL_PROJECT_ID="$INFISICAL_PROJECT_ID" INFISICAL_ENVIRONMENT="$INFISICAL_ENVIRONMENT" \
        INFISICAL_DOMAIN="$INFISICAL_DOMAIN" INFISICAL_TOKEN="${INFISICAL_TOKEN:-}" \
        ENVIRONMENT_DIR="$ENVIRONMENT_DIR" bash "$ENVIRONMENT_DIR/bootstrap.sh"
}

main "$@"
