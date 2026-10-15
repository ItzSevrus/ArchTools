# Qylock Setup

A transparent, cross-distribution Bash installer for [Qylock](https://github.com/Darkkal44/qylock), the SDDM lock-screen theme collection by Darkkal44.

`qylock-setup` automates dependency installation, clones the upstream repository into a temporary directory, and launches its official `sddm.sh` installer. It also provides a tracked uninstall operation.

## Features

- **Simple CLI:** Separate `install` and `uninstall` commands.
- **Automatic package manager detection:** Supports pacman, APT, DNF, and Zypper.
- **Dependency management:** Checks and installs required packages before launching the installer.
- **Temporary cloning:** Downloads Qylock into a temporary directory and removes the clone on exit.
- **Upstream installation:** Runs Qylock's own interactive `sddm.sh` script.
- **Configuration backup:** Saves the existing SDDM theme configuration before installation.
- **Tracked uninstall:** Removes the recorded theme and attempts to restore the previous configuration.
- **Transparent operation:** Displays planned actions, package operations, warnings, and errors.
- **Conservative cleanup:** Does not uninstall SDDM or remove dependencies during uninstall.

## Requirements

- Bash
- Git
- `sudo` privileges
- An internet connection
- A supported Linux distribution
- An SDDM-compatible desktop environment or display-manager setup

## Installation

Make the script executable and install it system-wide:

```bash
chmod +x qylock-setup
sudo install -Dm755 qylock-setup /usr/local/bin/qylock-setup
```

Confirm that it is accessible:

```bash
qylock-setup help
```

## Usage

### Install Qylock

```bash
qylock-setup install
```

The installer will:

1. Detect your package manager.
2. Display the dependency plan and request confirmation.
3. Install required dependencies and attempt to install optional `fzf`.
4. Clone the Qylock repository into a temporary directory.
5. Back up the existing SDDM theme configuration, if present.
6. Launch the upstream `sddm.sh` installer.
7. Record the selected theme for later removal.
8. Clean up the temporary clone when the script exits.

Follow the upstream installer's prompts to choose your theme and Qt compatibility mode.

### Uninstall Qylock

```bash
qylock-setup uninstall
```

The uninstall operation uses the recorded theme name to remove the corresponding theme directory. If the tracked theme remains active, it attempts to restore the previous SDDM configuration or remove the configuration file created for Qylock.

It does **not** uninstall SDDM, remove dependencies, or intentionally delete other theme directories.

### Display help

```bash
qylock-setup help
```

## Supported distributions

| Package manager | Distribution examples | Status |
|---|---|---|
| pacman | Arch Linux and derivatives | Supported |
| APT | Debian, Ubuntu and derivatives | Supported, subject to package availability |
| DNF | Fedora and derivatives | Supported, subject to package availability |
| Zypper | openSUSE | Supported, subject to package availability |
| Nix | NixOS | Use the upstream Nix flake instead |

Package names differ between distributions and release versions. Some Qt 6 modules may be unavailable in older repositories. The installer stops if a required dependency cannot be installed.

## Dependencies

The dependency groups below are based on Qylock's documented SDDM setup requirements. Exact package names depend on your distribution.

| Category | Dependencies |
|---|---|
| Display manager | SDDM |
| Qt 6 | Qt Declarative, Qt 6 Compatibility, Qt SVG |
| Multimedia | Qt Multimedia and FFmpeg backend where available |
| GStreamer | Base, Good, Bad and Ugly plugin sets |
| Optional utility | `fzf` |

### Qt 5 legacy mode

Some systems use a Qt 5-based SDDM while Qylock's themes target Qt 6. The upstream README documents a legacy compatibility mode with these dependencies:

- `sddm`
- `qt5-declarative`
- `qt5-graphicaleffects`
- `qt5-quickcontrols2`
- `qt5-multimedia`
- GStreamer Base, Good, Bad and Ugly plugins
- `perl`

Select the compatibility option in the upstream installer when appropriate. Installing these packages does not guarantee that every theme works on every legacy system.

## Configuration and state

The installer stores per-user tracking information in:

```text
${XDG_STATE_HOME:-~/.local/state}/qylock-setup/
```

This directory contains the recorded theme name and, when available, a backup of the previous SDDM theme configuration.

The upstream installer manages the system theme files and configuration. The wrapper does not replace the upstream theme installation mechanism.

## Safety and limitations

- Review the upstream repository and installation script before running third-party code with elevated privileges.
- Dependency installation changes system packages and may require administrator authentication.
- The upstream installer is interactive and controls the actual theme installation.
- Uninstall requires the state directory created by a successful installation. It does not guess which theme should be removed.
- The wrapper cannot guarantee recovery of theme files that the upstream installer overwrites.
- Configuration restoration is based on the tracked theme being active. If the active theme has changed, the wrapper preserves the newer configuration.
- The installer does not enable, disable, or remove SDDM.
- Dependencies are deliberately retained after uninstall because other applications may use them.
- If installation fails, inspect the SDDM configuration and theme directory before retrying.

## Upstream project

- Repository: https://github.com/Darkkal44/qylock
- Upstream installation script: `sddm.sh`
- Upstream documentation: [Qylock README](https://github.com/Darkkal44/qylock/blob/main/README.md)

## License

This installer is an independent wrapper around Qylock. Refer to the upstream repository for Qylock's licensing and attribution requirements. Add a separate license for this wrapper if you intend to redistribute it.
