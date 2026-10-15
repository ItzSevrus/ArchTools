# Qylock Setup
A cross-distribution installer and uninstaller for Qylock SDDM themes.

## Description
`qylock-setup` automates Qylock setup by detecting the system package manager, installing dependencies, cloning the upstream repository into a temporary directory, and running its interactive SDDM installation script.

## Commands
- `qylock-setup install` — Install dependencies and launch the Qylock SDDM installer.
- `qylock-setup uninstall` — Remove the tracked Qylock theme and restore the previous configuration when possible.
- `qylock-setup help` — Display usage information.

## Supported package managers
- pacman
- APT
- DNF
- Zypper
NixOS users should use the upstream Nix flake.

## Important notes
- Requires Bash, Git, and sudo privileges.
- Displays the planned operations before making changes.
- Does not uninstall SDDM or dependencies during removal.
- Uninstall relies on tracking information created during installation.
- The upstream installation script is interactive.

## Upstream
https://github.com/Darkkal44/qylock
Qylock Setup is an independent wrapper and is not an official upstream Qylock project.
