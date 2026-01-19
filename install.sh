#!/bin/bash

# Hyprland Dotfiles Installer with Gum
# Description: Interactive installer for Hyprland configuration

set -e

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
NC='\033[0m'

KAGUYADOTS_DIR="$HOME/KaguyaDots"
KAGUYADOTSAPPSDIR="$HOME/KaguyaDots/apps"

REPO_URL="https://github.com/PcKaguya/KaguyaDots.git"
# https://github.com/Nurysso/KaguyaDots/blob/main/scripts/install/arch.sh
# https://raw.githubusercontent.com/Nurysso/KaguyaDots/refs/heads/main/scripts/install/arch.sh
SCRIPT_BASE_URL="https://raw.githubusercontent.com/PcKaguya/KaguyaDots/main/scripts/install"
OS=""
PACKAGE_MANAGER=""

detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    case "$ID" in
    arch | manjaro | endeavouros | cachyos)
      OS="arch"
      ;;
    fedora)
      OS="fedora"
      ;;
    ubuntu | debian | pop | linuxmint)
      OS="ubuntu"
      ;;
    *)
      echo -e "${RED}Error: OS '$ID' is not supported!${NC}"
      exit 1
      ;;
    esac
  else
    echo -e "${RED}Error: Cannot detect OS!${NC}"
    exit 1
  fi
}

# Install gum based on detected OS
install_gum() {
  echo -e "${YELLOW}Installing gum...${NC}"
  echo ""

  case "$OS" in
  arch)
    if command -v pacman &>/dev/null; then
      sudo pacman -S --noconfirm gum
    else
      echo -e "${RED}pacman not found!${NC}"
      return 1
    fi
    ;;
  fedora)
    if command -v dnf &>/dev/null; then
      sudo dnf install -y gum
    else
      echo -e "${RED}dnf not found!${NC}"
      return 1
    fi
    ;;
  ubuntu)
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
    sudo apt update && sudo apt install -y gum
    ;;
  *)
    echo -e "${RED}Unsupported OS for automatic gum installation${NC}"
    return 1
    ;;
  esac

  if command -v gum &>/dev/null; then
    echo -e "${GREEN}✓ Gum installed successfully!${NC}"
    return 0
  else
    echo -e "${RED}✗ Gum installation failed!${NC}"
    return 1
  fi
}


check_dependencies() {
  local missing=()

  # Check gum
  if ! command -v gum &>/dev/null; then missing+=("gum"); fi
  # Check figlet
  if ! command -v figlet &>/dev/null; then missing+=("figlet"); fi
  # Check tte
  if ! command -v tte &>/dev/null; then missing+=("tte"); fi

  if [ ${#missing[@]} -eq 0 ]; then
    return 0
  fi

  echo -e "${RED}Missing dependencies: ${missing[*]}${NC}"
  echo -e "${YELLOW}Required for this installer to work.${NC}"
  echo ""

  # Detect AUR helper
  local aur_helper=""
  if command -v paru &>/dev/null; then
    aur_helper="paru"
  elif command -v yay &>/dev/null; then
    aur_helper="yay"
  fi

  # Prompt user to install
  read -p "Would you like to install missing dependencies now? (y/n): " -n 1 -r
  echo ""

  if [[ $REPLY =~ ^[Yy]$ ]]; then
    if install_dependencies "${missing[@]}"; then
      echo ""
      echo -e "${GREEN}All dependencies installed successfully!${NC}"
      echo -e "${GREEN}Continuing with installation...${NC}"
      echo ""
      sleep 1
    else
      echo -e "${RED}Failed to install dependencies. Exiting.${NC}"
      exit 1
    fi
  else
    echo ""
    echo -e "${YELLOW}Installation cancelled.${NC}"
    echo -e "${BLUE}Install dependencies manually and run this script again.${NC}"
    echo ""
    echo "Manual installation instructions (Arch):"
    echo -e "${GREEN}  sudo pacman -S figlet gum${NC}"
    echo -e "${GREEN}  $aur_helper -S terminaltexteffects${NC}"
    echo ""
    echo "Other distros:"
    case "$OS" in
      fedora)
        echo -e "${GREEN}  sudo dnf install gum figlet${NC}"
        echo -e "${GREEN}  pip install terminaltexteffects${NC}"
        ;;
      ubuntu)
        echo -e "${GREEN}  sudo apt install figlet${NC}"
        echo -e "${GREEN}  # Gum (Charm repo):${NC}"
        echo -e "${GREEN}  sudo mkdir -p /etc/apt/keyrings${NC}"
        echo -e "${GREEN}  curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg${NC}"
        echo -e "${GREEN}  echo \"deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *\" | sudo tee /etc/apt/sources.list.d/charm.list${NC}"
        echo -e "${GREEN}  sudo apt update && sudo apt install gum${NC}"
        echo -e "${GREEN}  pip install terminaltexteffects${NC}"
        ;;
      *)
        echo "  Visit: https://github.com/charmbracelet/gum"
        echo "  sudo pacman -S figlet (or equivalent)"
        echo "  pip install terminaltexteffects"
        ;;
    esac
    echo ""
    exit 1
  fi
}

install_dependencies() {
  local deps=("$@")

  case "$OS" in
    arch)
      # Install official packages first
      sudo pacman -S --noconfirm "${deps[@]}" 2>/dev/null || true

      # Install tte via AUR helper if missing
      if ! command -v tte &>/dev/null; then
        local aur_helper=""
        if command -v paru &>/dev/null; then
          aur_helper="paru"
        elif command -v yay &>/dev/null; then
          aur_helper="yay"
        else
          echo -e "${RED}No AUR helper (paru/yay) found. Install paru/yay first.${NC}"
          return 1
        fi

        echo "Installing terminaltexteffects via $aur_helper..."
        $aur_helper -S --noconfirm terminaltexteffects || {
          echo -e "${RED}Failed to install terminaltexteffects via AUR.${NC}"
          echo -e "${YELLOW}Trying pip install as fallback...${NC}"
          pip install terminaltexteffects || return 1
        }
      fi
      ;;
    *)
      # Fallback for other distros (pip for tte)
      pip install terminaltexteffects || return 1
      ;;
  esac

  return 0
}


# Check if tte is installed
check_tte() {
  if ! command -v tte &>/dev/null; then
    gum style --foreground 220 "⚠ TTE (Terminal Text Effects) not found"
    gum style --foreground 220 "Install with: pip install terminaltexteffects"
    echo ""
    if gum confirm "Continue without TTE effects?"; then
      return 0
    else
      exit 1
    fi
  fi
}

# Use tte if available, otherwise fallback to echo
fancy_echo() {
  local text="$1"
  local effect="${2:-slide}"

  if command -v tte &>/dev/null; then
    echo "$text" | tte "$effect" --movement-speed 5 2>/dev/null || echo "$text"
  else
    echo "$text"
  fi
}

# Check OS and display appropriate messages
check_OS() {
  case "$OS" in
  arch)
    fancy_echo "✓ Detected OS: Arch Linux" "slide"
    ;;
  fedora)
    gum style --foreground 220 --bold "⚠️ Warning: Script has not been tested on Fedora!"
    gum style --foreground 220 "Proceed at your own risk or follow the Fedora guide if available at:"
    gum style --foreground 220 "https://github.com/KaguyaDots/KaguyaDots/tree/main/documentation/install-fedora.md"
    if ! gum confirm "Continue with Fedora installation?"; then
      exit 1
    fi
    ;;
  ubuntu)
    gum style --foreground 220 --bold "⚠️ Warning: Ubuntu/Debian-based OS detected!"
    gum style --foreground 220 "KaguyaDots installer support for Ubuntu is experimental."
    gum style --foreground 220 "Manual installation instructions:"
    gum style --foreground 220 "https://github.com/KaguyaDots/KaguyaDots/tree/main/documentation/install-ubuntu.md"
    if ! gum confirm "Continue with Ubuntu installation?"; then
      exit 1
    fi
    ;;
  esac
}

# Download and execute OS-specific installation script
run_os_script() {
  local script_name="${OS}.sh"
  local script_url="${SCRIPT_BASE_URL}/${script_name}"
  local temp_script="/tmp/kaguyadots_install_${OS}.sh"

  gum style --foreground 82 "Downloading ${OS} installation script..."
  echo ""

  if curl -fsSL "$script_url" -o "$temp_script"; then
    fancy_echo "✓ Script downloaded successfully" "slide"
    chmod +x "$temp_script"
    echo ""
    gum style --foreground 220 "Executing ${OS} installation script..."
    echo ""

    # Execute the script and capture exit code
    # Check if script succeeded before continuing
    if bash "$temp_script"; then
      fancy_echo "✓ Installation script completed successfully" "beams"
      rm -f "$temp_script"
      return 0
    else
      local exit_code=$?

      # Clean up temp script
      rm -f "$temp_script"

      # Check if it was a user cancellation (exit 1) or actual error
      if [ $exit_code -eq 1 ]; then
        gum style --foreground 220 "Installation cancelled by user"
      else
        gum style --foreground 196 "✗ Installation script failed with exit code: $exit_code"
      fi

      # Exit the main installer too
      exit $exit_code
    fi
  else
    gum style --foreground 196 "✗ Failed to download installation script from:"
    gum style --foreground 196 "  $script_url"
    echo ""
    gum style --foreground 220 "Please check:"
    gum style --foreground 220 "  1. Your internet connection"
    gum style --foreground 220 "  2. The script exists in the repository"
    gum style --foreground 220 "  3. The URL is correct"
    exit 1
  fi
}

# Set script permissions in the cloned repo
set_repo_script_permissions() {
  gum style --border double --padding "1 2" --border-foreground 212 "Setting Script Permissions"
  
  if [ -d "$KAGUYADOTS_DIR/config" ]; then
    find "$KAGUYADOTS_DIR/config" -type f -name "*.sh" -exec chmod +x {} +
    fancy_echo "✓ Script permissions set in cloned repository."
  else
    gum style --foreground 220 "⚠ Config directory not found in repo, skipping permission set."
  fi
}

# Build Wails applications
build_apps() {
  gum style --border double --padding "1 2" --border-foreground 212 "Building Helper Applications"

  if ! command -v wails &>/dev/null; then
    gum style --foreground 220 "ℹ Wails CLI not found. Using pre-built application binaries."
    gum style --foreground 220 "  To build from source, install Wails (wails.io) and re-run."
    return
  fi

  if gum confirm "Wails CLI detected. Do you want to rebuild the helper applications from source?"; then
      local apps_dir="$KAGUYADOTS_DIR/apps"
      local apps_to_build=("KaguyaDots-Help" "Pulse" "Aoiler")

      for app in "${apps_to_build[@]}"; do
        local app_path="$apps_dir/$app"
        if [ -d "$app_path" ]; then
          fancy_echo "Building $app..." "slide"
          # The (cd ... && wails build) runs in a subshell, so output is clean
          if (cd "$app_path" && wails build); then
            fancy_echo "✓ $app built successfully!"
          else
            gum style --foreground 196 "✗ Error building $app! Check for errors above."
          fi
        else
          gum style --foreground 220 "⚠ App directory not found: $app_path"
        fi
      done
  else
      gum style --foreground 82 "✓ Skipping app rebuild. Using pre-built binaries."
  fi
}

# Clone dotfiles
clone_dotfiles() {
  gum style --border double --padding "1 2" --border-foreground 212 "Cloning KaguyaDots Dotfiles"

  if [ -d "$KAGUYADOTS_DIR" ]; then
    if gum confirm "KaguyaDots directory already exists. Remove and re-clone?"; then
      rm -rf "$KAGUYADOTS_DIR"
    else
      gum style --foreground 220 "Using existing directory..."
      return
    fi
  fi

  gum style --foreground 220 "Cloning repository..."
  if ! git clone --depth 1 "$REPO_URL" "$KAGUYADOTS_DIR"; then
    gum style --foreground 196 "✗ Error cloning repository!"
    gum style --foreground 196 "Check your internet connection and try again."
    exit 1
  fi

  if [ ! -d "$KAGUYADOTS_DIR/config" ]; then
    gum style --foreground 196 "✗ Error: Config directory not found in cloned repo!"
    exit 1
  fi

  fancy_echo "✓ Dotfiles cloned successfully!" "beams"
}

# Install shell scripts to ~/.local/bin
install_shell_scripts() {
  gum style --border double --padding "1 2" --border-foreground 212 "Installing Shell Scripts"

  mkdir -p "$HOME/.local/bin"

  local scripts_dir="$KAGUYADOTS_DIR/config/local-bin"

  if [ ! -d "$scripts_dir" ]; then
    gum style --foreground 220 "⚠ Scripts directory not found at $scripts_dir"
    return
  fi

  # Install kaguyadots.sh
  if [ -f "$scripts_dir/kaguyadots.sh" ]; then
    fancy_echo "Installing kaguyadots script..." "slide"
    cp "$scripts_dir/kaguyadots.sh" "$HOME/.local/bin/kaguyadots"
    chmod +x "$HOME/.local/bin/kaguyadots"
    fancy_echo "✓ kaguyadots installed to ~/.local/bin/kaguyadots" "slide"
  else
    gum style --foreground 220 "⚠ kaguyadots.sh not found at $scripts_dir/kaguyadots.sh"
  fi

  # Install freya.sh
  if [ -f "$scripts_dir/file_convert.sh" ]; then
    fancy_echo "Installing freya script..." "slide"
    cp "$scripts_dir/file_convert.sh" "$HOME/.local/bin/file_convert"
    chmod +x "$HOME/.local/bin/file_convert"
    fancy_echo "✓ freya installed to ~/.local/bin/file_convert" "slide"
  else
    gum style --foreground 220 "⚠ freya.sh not found at $scripts_dir/file_convert.sh"
  fi

  echo ""
  gum style --foreground 82 "✓ Shell scripts installed successfully!"
}

# Move configs from cloned repo to ~/.config
move_config() {
  gum style --border double --padding "1 2" --border-foreground 212 "Installing Configuration Files"

  if [ ! -d "$KAGUYADOTS_DIR/config" ]; then
    gum style --foreground 196 "Error: Config directory not found at $KAGUYADOTS_DIR/config"
    exit 1
  fi

  mkdir -p "$CONFIGDIR"
  mkdir -p "$HOME/.local/bin"

  # Copy all config directories except shell rc files
  for item in "$KAGUYADOTS_DIR/config"/*; do
    if [ -d "$item" ]; then
      local item_name=$(basename "$item")

      # Skip local-bin directory (handled separately)
      if [ "$item_name" = "local-bin" ]; then
        continue
      fi

      # Handle terminal configs - only install selected terminal
      case "$item_name" in
        alacritty|foot|ghostty|kitty)
          if [ "$item_name" = "$USER_TERMINAL" ]; then
            fancy_echo "Installing $item_name config..." "slide"
            cp -rT "$item" "$CONFIGDIR/$item_name"
          fi
          ;;
        *)
          # Install all other configs
          fancy_echo "Installing $item_name..." "slide"
          cp -rT "$item" "$CONFIGDIR/$item_name"
          ;;
      esac
    fi
  done

  # Handle shell rc files
  if [ -f "$KAGUYADOTS_DIR/config/zshrc" ]; then
    fancy_echo "Installing .zshrc..." "slide"
    cp "$KAGUYADOTSDIR/config/zshrc" "$HOME/.zshrc"
    fancy_echo "✓ ZSH config installed" "slide"
  else
    gum style --foreground 220 "⚠ zshrc not found in config directory"
  fi

  if [ -f "$KAGUYADOTS_DIR/config/bashrc" ]; then
    fancy_echo "Installing .bashrc..." "slide"
    cp "$KAGUYADOTSDIR/config/bashrc" "$HOME/.bashrc"
    fancy_echo "✓ BASH config installed" "slide"
  else
    gum style --foreground 220 "⚠ bashrc not found in config directory"
  fi

  # Create compatibility symlink for older directory name (kaguya_dots -> kaguyadots)
  if [ -d "$CONFIGDIR/kaguya_dots" ] && [ ! -e "$CONFIGDIR/kaguyadots" ]; then
    fancy_echo "Creating compatibility symlink: $CONFIGDIR/kaguyadots -> $CONFIGDIR/kaguya_dots" "slide"
    ln -s "$CONFIGDIR/kaguya_dots" "$CONFIGDIR/kaguyadots"
  fi

  # Ensure Waybar has a color.css; prefer the canonical kaguyadots path but fall back safely.
  mkdir -p "$CONFIGDIR/waybar"
  if [ -f "$CONFIGDIR/kaguyadots/kaguyadots.css" ]; then
    ln -sf "$CONFIGDIR/kaguyadots/kaguyadots.css" "$CONFIGDIR/waybar/color.css"
  elif [ -f "$CONFIGDIR/kaguya_dots/kaguyadots.css" ]; then
    ln -sf "$CONFIGDIR/kaguya_dots/kaguyadots.css" "$CONFIGDIR/waybar/color.css"
  elif [ -f "$KAGUYADOTS_DIR/config/kaguya_dots/kaguyadots.css" ]; then
    # Use repository default as a last resort (useful for fresh installs)
    ln -sf "$KAGUYADOTS_DIR/config/kaguya_dots/kaguyadots.css" "$CONFIGDIR/waybar/color.css"
  else
    # Create a minimal placeholder so Waybar won't fail on first run.
    echo "/* KaguyaDots placeholder colors - run update_kaguyadots_colors.sh to generate real colors */" > "$CONFIGDIR/waybar/color.css"
  fi

  # Install shell scripts
  install_shell_scripts

  # Install apps from apps directory
  install_app "Pulse" "$KAGUYADOTSAPPSDIR/Pulse/build/bin/Pulse"
  install_app "KaguyaDots-Settings" "$KAGUYADOTSAPPSDIR/KaguyaDots-Help/build/bin/KaguyaDots-Settings"
  install_app "Aoiler" "$KAGUYADOTSAPPSDIR/Aoiler/build/bin/Aoiler"

  echo ""
  fancy_echo "✓ Configuration files installed successfully!" "beams"
}

# Helper function to install apps
install_app() {
  local app_name="$1"
  local app_path="$2"
  local app_display="${3:-$app_name}"

  if [ -f "$app_path" ]; then
    fancy_echo "Installing $app_display..." "slide"
    cp "$app_path" "$HOME/.local/bin/$app_name"
    chmod +x "$HOME/.local/bin/$app_name"
    fancy_echo "✓ $app_display installed to ~/.local/bin/$app_name" "slide"
  else
    gum style --foreground 220 "⚠ $app_display binary not found at $app_path"
  fi
}

backup_config() {
  gum style --border double --padding "1 2" --border-foreground 212 "Backing Up Existing Configs"

  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_dir="$HOME/.cache/kaguyadots-backup/kaguyadots-$timestamp"

  # List of config directories to check
  local config_dirs=(
    "alacritty" "cava" "fastfetch" "foot" "gtk-3.0" "kaguyadots" "kitty"
    "quickshell" "starship" "wallust" "waypaper" "zsh" "bash" "fish"
    "ghostty" "gtk-4.0" "hypr" "matugen" "rofi" "swaync" "waybar" "wlogout"
  )

  # Check for shell rc files separately
  local shell_files=()
  [ -f "$HOME/.zshrc" ] && shell_files+=(".zshrc")
  [ -f "$HOME/.bashrc" ] && shell_files+=(".bashrc")

  local backed_up=false

  # Backup config directories
  for dir in "${config_dirs[@]}"; do
    if [ -d "$HOME/.config/$dir" ]; then
      if [ "$backed_up" = false ]; then
        mkdir -p "$backup_dir/config"
        backed_up=true
      fi
      fancy_echo "Backing up: $dir" "slide"
      cp -r "$HOME/.config/$dir" "$backup_dir/config/"
    fi
  done

  # Backup shell rc files
  for file in "${shell_files[@]}"; do
    if [ "$backed_up" = false ]; then
      mkdir -p "$backup_dir"
      backed_up=true
    fi
    fancy_echo "Backing up: $file" "slide"
    cp "$HOME/$file" "$backup_dir/"
  done

  if [ "$backed_up" = true ]; then
    echo ""
    fancy_echo "✓ Backup created at: $backup_dir" "beams"
    echo "$backup_dir" > "$HOME/.cache/kaguyadots_last_backup.txt"
  else
    gum style --foreground 220 "No existing configs found to backup"
  fi
}
# Main function
main() {
  # Parse arguments
  case "${1:-}" in
    --help | -h)
      clear
      echo -e "${YELLOW}Prerequisites:${NC}"
      echo "  • gum - Interactive CLI tool"
      echo "    (Will be installed automatically if missing)"
      echo ""
      echo "  • tte - Terminal text effects"
      echo "    Install: pip install terminaltexteffects"
      echo ""
      echo "  • paru (recommended) - AUR helper (Arch only)"
      echo "    Install: https://github.com/Morganamilo/paru#installation"
      echo ""
      echo -e "${YELLOW}Usage:${NC}"
      echo "  ./install.sh              Run the full installer"
      echo "  ./install.sh --no-deps    Skip dependency installation"
      echo "  ./install.sh --help       Show this message"
      echo "  ./install.sh --dry-run    Simulate installation"
      echo ""
      echo -e "${YELLOW}Options:${NC}"
      echo "  --no-deps    Skip OS-specific dependency installation"
      echo "               Only clones repo, backs up configs, and installs dotfiles"
      echo ""
      echo "Supported distributions: Arch, Fedora, Ubuntu/Debian(maybe in future for now run with --no-deps)"
      exit 0
      ;;
    --dry-run)
      echo -e "${BLUE}The \"I want to feel productive without doing anything mode\"${NC}"
      echo -e "${YELLOW}Simulating installation...${NC}"
      sleep 1
      echo ""
      echo -e "${GREEN}✓ System check: Passed (probably)${NC}"
      echo -e "${GREEN}✓ Packages: Would install ~47 packages${NC}"
      echo -e "${GREEN}✓ Configs: Would copy lots of dotfiles${NC}"
      echo ""
      echo -e "${YELLOW}Congratulations! You've successfully done... nothing.${NC}"
      echo -e "${ORANGE}Run without --dry-run when you're ready to actually install.${NC}"
      echo ""
      echo -e "${RED}Pro tip: Dry runs don't make your setup any cooler.${NC}"
      exit 0
      ;;
    --no-deps)
      # No-deps workflow
      backup_config
      echo ""
      clone_dotfiles
      echo ""
      set_repo_script_permissions
      echo ""
      build_apps
      echo ""
      move_config
      echo ""
      exit 0
      ;;
    -*)
      echo -e "${RED}Unknown option: $1${NC}"
      echo -e "${BLUE}Try: ./install.sh --help${NC}"
      exit 1
      ;;
  esac

  # Full installation workflow
  detect_os
  check_dependencies
  check_tte
  clear

  if command -v tte &>/dev/null; then
    figlet -f slant "KaguyaDots Dotfiles Installer" | tte laseretch --etch-speed 10
    echo 'Preparing to install Hyprland configuration...' | tte slide --movement-speed 0.5
  else
    gum style \
      --foreground 82 \
      --border-foreground 82 \
      --border double \
      --align center \
      --width 70 \
      --margin "1 2" \
      --padding "2 4" \
      'KaguyaDots Dotfiles Installer' \
      '' \
      'Preparing to install Hyprland configuration...'
  fi

  echo ""
  check_OS
  echo ""
  run_os_script

  backup_config
  echo ""
  clone_dotfiles
  echo ""
  set_repo_script_permissions
  echo ""
  build_apps
  echo ""
  move_config
  echo ""
}

# Run main function with arguments
main "$@"
