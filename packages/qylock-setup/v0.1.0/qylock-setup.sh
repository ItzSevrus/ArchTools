
#!/usr/bin/env bash
set -Eeuo pipefail

# Qylock Setup
# Install:   qylock-setup install
# Uninstall: qylock-setup uninstall

readonly APP="qylock-setup"
readonly REPO_URL="https://github.com/Darkkal44/qylock.git"
readonly REPO_NAME="qylock"
readonly SDDM_CONF="/etc/sddm.conf.d/theme.conf"
readonly SDDM_THEMES="/usr/share/sddm/themes"
readonly STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/qylock-setup"

readonly C_RESET=$'\033[0m'
readonly C_BLUE=$'\033[38;2;122;162;247m'
readonly C_GREEN=$'\033[38;2;158;206;106m'
readonly C_YELLOW=$'\033[38;2;224;175;104m'
readonly C_RED=$'\033[38;2;247;118;142m'
readonly C_BOLD=$'\033[1m'

TMP_DIR=""

log()     { printf '%s[*]%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
success() { printf '%s[OK]%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn()    { printf '%s[!]%s %s\n' "$C_YELLOW" "$C_RESET" "$*"; }
error()   { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; }
die()     { error "$*"; exit 1; }

header() {
    printf '\n%s%s' "$C_BLUE" "$C_BOLD"
    printf '========================================\n'
    printf '             QYLOCK SETUP\n'
    printf '========================================\n'
    printf '%s\n\n' "$C_RESET"
}

cleanup() {
    if [[ -n "$TMP_DIR" && -d "$TMP_DIR" ]]; then
        log "Removing temporary directory: $TMP_DIR"
        rm -rf -- "$TMP_DIR"
    fi
}
trap cleanup EXIT

need_command() {
    command -v "$1" >/dev/null 2>&1 ||
        die "Required command '$1' is missing."
}

confirm() {
    local answer
    read -r -p "$1 [y/N]: " answer
    [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]]
}

detect_package_manager() {
    if [[ -f /etc/NIXOS ]]; then
        die "NixOS detected. Use Qylock's Nix flake/module instead."
    fi

    if command -v pacman >/dev/null 2>&1; then
        PKG_MANAGER="pacman"
    elif command -v apt-get >/dev/null 2>&1; then
        PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
    elif command -v zypper >/dev/null 2>&1; then
        PKG_MANAGER="zypper"
    else
        die "Unsupported package manager. Supported: pacman, apt, dnf, zypper."
    fi

    success "Detected package manager: $PKG_MANAGER"
}

# Package mappings are distro-specific. Required dependencies are
# checked individually so one unavailable package does not hide others.
install_one_package() {
    local package="$1"
    local optional="${2:-no}"

    log "Checking/installing package: $package"

    case "$PKG_MANAGER" in
        pacman)
            if pacman -Q "$package" >/dev/null 2>&1; then
                success "$package is already installed."
                return 0
            fi
            if sudo pacman -S --needed --noconfirm "$package"; then
                success "Installed $package."
                return 0
            fi
            ;;
        apt)
            if dpkg-query -W -f='${Status}' "$package" 2>/dev/null |
                grep -q 'install ok installed'; then
                success "$package is already installed."
                return 0
            fi
            if ! apt-cache show "$package" >/dev/null 2>&1; then
                warn "Package not found in configured APT repositories: $package"
                [[ "$optional" == yes ]] && return 0
                return 1
            fi
            if sudo apt-get install -y "$package"; then
                success "Installed $package."
                return 0
            fi
            ;;
        dnf)
            if rpm -q "$package" >/dev/null 2>&1; then
                success "$package is already installed."
                return 0
            fi
            if sudo dnf install -y "$package"; then
                success "Installed $package."
                return 0
            fi
            ;;
        zypper)
            if rpm -q "$package" >/dev/null 2>&1; then
                success "$package is already installed."
                return 0
            fi
            if sudo zypper --non-interactive install "$package"; then
                success "Installed $package."
                return 0
            fi
            ;;
    esac

    if [[ "$optional" == yes ]]; then
        warn "Could not install optional package: $package"
        return 0
    fi

    error "Could not install required package: $package"
    return 1
}

install_dependencies() {
    local required=()
    local optional=()
    local package

    case "$PKG_MANAGER" in
        pacman)
            required=(
                sddm
                qt6-declarative
                qt6-5compat
                qt6-svg
                qt6-multimedia
                qt6-multimedia-ffmpeg
                gst-plugins-base
                gst-plugins-good
                gst-plugins-bad
                gst-plugins-ugly
            )
            optional=(fzf)
            ;;
        apt)
            # Qt 6 QML modules and multimedia support.
            # Availability varies across Debian/Ubuntu releases.
            required=(
                sddm
                qml6-module-qtquick
                qml6-module-qtquick-controls
                qml6-module-qtquick-layouts
                qml6-module-qtquick-window
                qml6-module-qtmultimedia
                qml6-module-qtsvg
                gstreamer1.0-plugins-base
                gstreamer1.0-plugins-good
                gstreamer1.0-plugins-bad
                gstreamer1.0-plugins-ugly
            )
            optional=(
                qml6-module-qt5compat-graphicaleffects
                fzf
            )
            ;;
        dnf)
            required=(
                sddm
                qt6-qtdeclarative
                qt6-qt5compat
                qt6-qtsvg
                qt6-qtmultimedia
                gstreamer1-plugins-base
                gstreamer1-plugins-good
                gstreamer1-plugins-bad-free
                gstreamer1-plugins-ugly
            )
            optional=(fzf)
            ;;
        zypper)
            required=(
                sddm
                qt6-declarative-imports
                qt6-5compat
                qt6-svg
                qt6-multimedia
                gstreamer-plugins-base
                gstreamer-plugins-good
                gstreamer-plugins-bad
                gstreamer-plugins-ugly
            )
            optional=(fzf)
            ;;
    esac

    printf '\n%sDependency plan%s\n' "$C_BOLD" "$C_RESET"
    printf 'Required packages:\n'
    printf '  - %s\n' "${required[@]}"
    printf 'Optional packages:\n'
    printf '  - %s\n' "${optional[@]}"
    printf '\n'

    warn "Package names differ across distribution releases."
    warn "This script will stop if a required package cannot be installed."
    warn "No package will be removed during uninstall."

    confirm "Proceed with dependency installation?" ||
        die "Cancelled before installing dependencies."

    case "$PKG_MANAGER" in
        apt)
            log "Refreshing APT package indexes..."
            sudo apt-get update
            ;;
        pacman)
            log "Refreshing Arch package databases..."
            sudo pacman -Sy
            ;;
        dnf)
            log "Refreshing DNF metadata..."
            sudo dnf makecache
            ;;
        zypper)
            log "Refreshing Zypper repositories..."
            sudo zypper refresh
            ;;
    esac

    local failed=0

    for package in "${required[@]}"; do
        if ! install_one_package "$package"; then
            failed=1
        fi
    done

    for package in "${optional[@]}"; do
        install_one_package "$package" yes || true
    done

    (( failed == 0 )) ||
        die "One or more required dependencies failed. Fix the errors and retry."

    command -v sddm >/dev/null 2>&1 ||
        die "SDDM executable is still missing after dependency installation."

    success "Required dependency installation completed."
}

prepare_state() {
    if [[ -e "$STATE_DIR/theme" ]]; then
        die "An existing Qylock installation is tracked at $STATE_DIR.
Run '$APP uninstall' first, then install again."
    fi

    mkdir -p "$STATE_DIR"
    chmod 700 "$STATE_DIR"

    # Back up the exact configuration file this upstream script edits.
    if sudo test -f "$SDDM_CONF"; then
        sudo cat "$SDDM_CONF" > "$STATE_DIR/theme.conf.backup"
        touch "$STATE_DIR/had-config"
        chmod 600 "$STATE_DIR/theme.conf.backup"
        success "Saved a backup of $SDDM_CONF."
    else
        rm -f "$STATE_DIR/had-config" "$STATE_DIR/theme.conf.backup"
        success "No previous Qylock theme configuration exists."
    fi
}

install_qylock() {
    header

    need_command git
    need_command sudo
    need_command mktemp
    need_command grep
    need_command sed

    detect_package_manager

    if [[ -e "$STATE_DIR/theme" ]]; then
        die "Qylock is already tracked by this setup. Run '$APP uninstall' first."
    fi

    printf 'This operation will:\n'
    printf '  1. Install missing system dependencies.\n'
    printf '  2. Clone %s into a temporary directory.\n' "$REPO_URL"
    printf '  3. Back up the existing SDDM theme configuration, if present.\n'
    printf '  4. Run the upstream interactive sddm.sh installer.\n'
    printf '  5. Record the selected theme for future uninstall.\n'
    printf '  6. Delete the temporary clone after the operation.\n\n'

    warn "The upstream script uses sudo to write system theme files."
    warn "Review the upstream project before running third-party code."
    confirm "Continue with Qylock installation?" ||
        die "Cancelled by user."

    install_dependencies

    TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/qylock-setup.XXXXXXXX")"
    log "Temporary directory: $TMP_DIR"

    log "Cloning Qylock from GitHub..."
    git clone --depth 1 "$REPO_URL" "$TMP_DIR/$REPO_NAME"

    local repo_dir="$TMP_DIR/$REPO_NAME"
    [[ -f "$repo_dir/sddm.sh" ]] ||
        die "The cloned repository does not contain sddm.sh."

    prepare_state

    log "Starting upstream Qylock SDDM installer."
    log "Choose Qt6 or Qt5 Legacy according to your SDDM environment."
    log "Select your desired theme in the upstream menu."
    printf '\n'

    chmod +x "$repo_dir/sddm.sh"

    # Do not run the upstream installer as root; it calls sudo itself.
    if ! bash "$repo_dir/sddm.sh"; then
        warn "The upstream installer did not finish successfully."
        warn "The configuration backup has been retained at $STATE_DIR."
        die "Installation failed. Inspect SDDM settings before retrying."
    fi

    # Read the theme name from the configuration written by sddm.sh.
    local theme=""
    if sudo test -f "$SDDM_CONF"; then
        theme="$(sudo sed -n \
            's/^[[:space:]]*Current[[:space:]]*=[[:space:]]*//p' \
            "$SDDM_CONF" | tail -n 1)"
    fi

    # Only accept a simple directory name; upstream uses clockwork variants
    # as their own install directory names.
    if [[ -z "$theme" || "$theme" == */* ||
          "$theme" == "." || "$theme" == ".." ]]; then
        warn "Could not reliably determine the installed theme name."
        warn "The upstream installer may have been cancelled or its behavior changed."
        warn "Your backup is retained. No automatic uninstall tracking was created."
        die "Installation tracking failed."
    fi

    if ! sudo test -d "$SDDM_THEMES/$theme"; then
        warn "The expected theme directory does not exist: $SDDM_THEMES/$theme"
        die "Cannot verify the upstream installation."
    fi

    printf '%s\n' "$theme" > "$STATE_DIR/theme"
    chmod 600 "$STATE_DIR/theme"

    success "Qylock theme '$theme' installed."
    success "Uninstall tracking saved in $STATE_DIR."
    printf '\n'
    log "To remove the tracked theme later, run: $APP uninstall"
}

uninstall_qylock() {
    header

    need_command sudo

    if [[ ! -f "$STATE_DIR/theme" ]]; then
        die "No tracked installation was found for this user.
Expected state: $STATE_DIR/theme
This script will not guess which system theme to delete."
    fi

    local theme
    theme="$(<"$STATE_DIR/theme")"

    # Defensive validation before using a value in a system path.
    [[ "$theme" =~ ^[A-Za-z0-9._-]+$ ]] ||
        die "Invalid theme name in tracking file."

    local theme_path="$SDDM_THEMES/$theme"
    local current=""

    if sudo test -f "$SDDM_CONF"; then
        current="$(sudo sed -n \
            's/^[[:space:]]*Current[[:space:]]*=[[:space:]]*//p' \
            "$SDDM_CONF" | tail -n 1)"
    fi

    printf 'This operation will:\n'
    printf '  - Remove the tracked theme directory: %s\n' "$theme_path"
    printf '  - Restore the previous %s if a backup exists.\n' "$SDDM_CONF"
    printf '  - Otherwise remove the configuration file created by this installer.\n'
    printf '  - Leave SDDM and all installed dependencies untouched.\n'
    printf '  - Leave other theme directories untouched.\n\n'

    warn "The selected theme will no longer be available."
    if [[ "$current" != "$theme" ]]; then
        warn "The active theme setting has changed since installation."
        warn "The configuration will be left alone to avoid overwriting newer changes."
    fi

    confirm "Proceed with uninstall?" ||
        die "Uninstall cancelled."

    if [[ "$current" == "$theme" ]]; then
        if [[ -f "$STATE_DIR/had-config" &&
              -f "$STATE_DIR/theme.conf.backup" ]]; then
            log "Restoring the previous SDDM configuration..."
            sudo install -D -m 644 \
                "$STATE_DIR/theme.conf.backup" "$SDDM_CONF"
            success "Previous configuration restored."
        else
            log "Removing the configuration created for Qylock..."
            sudo rm -f -- "$SDDM_CONF"
            success "Qylock configuration removed."
        fi
    else
        warn "Preserving $SDDM_CONF because it no longer selects '$theme'."
    fi

    if sudo test -d "$theme_path"; then
        log "Removing tracked theme directory..."
        sudo rm -rf -- "$theme_path"
        success "Removed $theme_path."
    else
        warn "Theme directory already absent: $theme_path"
    fi

    rm -rf -- "$STATE_DIR"
    success "Qylock setup state removed."
    success "Uninstall completed. SDDM and dependencies were not removed."
}

usage() {
    cat <<'EOF'
qylock-setup — Qylock SDDM theme installer

Usage:
  qylock-setup install
  qylock-setup uninstall
  qylock-setup help

Supported package managers:
  pacman, apt, dnf, zypper

Notes:
  - Requires a normal user account with sudo access.
  - Does not enable, disable, or remove SDDM.
  - Does not uninstall packages during uninstall.
  - Keeps per-user tracking and the configuration backup in XDG_STATE_HOME
    or ~/.local/state/qylock-setup.
  - The upstream sddm.sh installer is interactive.
EOF
}

case "${1:-}" in
    install)
        install_qylock
        ;;
    uninstall)
        uninstall_qylock
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        usage
        exit 2
        ;;
esac

