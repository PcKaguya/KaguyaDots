#!/usr/bin/env bash
# QuickEdit.sh - Quick configuration editor/menu using rofi/dmenu/fzf
#
# Places to edit (configurable below) and a simple interactive picker
# that opens the selected file in $EDITOR (or a sensible default).
#
# Features:
#  - Uses rofi (preferred), falls back to fzf, dmenu, or plain read.
#  - Lets you pick a category (Waybar, Hyprland, KaguyaDots, Rofi, etc.)
#  - Lists files in the chosen category (searchable via rofi/fzf)
#  - Create new files if desired
#  - Opens file in a terminal editor (nvim/vim/nano/micro/emacs) inside $TERMINAL,
#    or launches GUI editors directly (code/gedit/etc) when detected.
#
# Install: place in ~/.config/hypr/UserScripts/QuickEdit.sh and make it executable:
#   chmod +x ~/.config/hypr/UserScripts/QuickEdit.sh
#
set -euo pipefail

# -------------------------
# Configuration
# -------------------------
# Preferred terminal/editor environment
TERMINAL="${TERMINAL:-kitty}"
EDITOR_CMD="${EDITOR:-${VISUAL:-nvim}}"

# Categories and their paths (add/remove as you like)
declare -A CATEGORIES=(
  [KaguyaDots]="$HOME/.config/kaguyadots"
  [Hyprland]="$HOME/.config/hypr"
  [Waybar]="$HOME/.config/waybar"
  [WaybarStyles]="$HOME/.config/waybar/style"
  [Rofi]="$HOME/.config/rofi"
  [SwayNC]="$HOME/.config/swaync"
  [Wlogout]="$HOME/.config/wlogout"
  [Waypaper]="$HOME/.config/waypaper"
  [UserScripts]="$HOME/.config/hypr/UserScripts"
  [Starship]="$HOME/.config/starship.toml"
  [GTK]="$HOME/.config/gtk-3.0"
  [Kitty]="$HOME/.config/kitty"
  [Alacritty]="$HOME/.config/alacritty"
)

# Max depth when scanning directories for files
MAX_DEPTH=3

# -------------------------
# Helpers: Menu chooser
# -------------------------
choose() {
  local prompt="$1"
  if command -v rofi >/dev/null 2>&1; then
    rofi -dmenu -i -p "$prompt" -mesg "" -lines 20
  elif command -v fzf >/dev/null 2>&1; then
    fzf --prompt "$prompt> " --height 20
  elif command -v dmenu >/dev/null 2>&1; then
    dmenu -i -p "$prompt"
  else
    # fallback to read
    read -r -p "$prompt: " result
    printf "%s" "$result"
  fi
}

notify_info() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u low "QuickEdit" "$1"
  else
    echo "QuickEdit: $1"
  fi
}

# -------------------------
# Utilities
# -------------------------
list_files_in() {
  local dir="$1"
  if [ -f "$dir" ]; then
    # single file
    printf "%s\n" "$(basename "$dir")"
    return 0
  fi
  if [ ! -d "$dir" ]; then
    return 1
  fi

  # Find files (skip .git). Print relative path.
  find "$dir" -maxdepth "$MAX_DEPTH" -type f \
    ! -path "*/.git/*" -printf "%P\n" 2>/dev/null | sort -u
}

open_in_editor() {
  local file="$1"
  # Resolve editor binary name (first token)
  local editor_bin
  editor_bin="$(printf '%s\n' "$EDITOR_CMD" | awk '{print $1}')"

  # Terminal editors -> open in $TERMINAL -e
  if command -v "$editor_bin" >/dev/null 2>&1; then
    case "$editor_bin" in
      nvim|vim|nano|micro|emacs)
        if command -v "$TERMINAL" >/dev/null 2>&1; then
          # Launch editor in terminal
          "$TERMINAL" -e "$editor_bin" "$file" &
          disown
        else
          "$editor_bin" "$file"
        fi
        ;;
      code|codium|subl|sublime_text|gedit|xed|kate)
        # GUI editors: launch in background
        "$editor_bin" "$file" >/dev/null 2>&1 &
        disown
        ;;
      *)
        # Unknown editor: try running it directly with arguments (best-effort)
        if command -v "$editor_bin" >/dev/null 2>&1; then
          # Try direct invocation; if it fails, fallback to xdg-open
          "$EDITOR_CMD" "$file" >/dev/null 2>&1 & disown || xdg-open "$file" >/dev/null 2>&1 || true
        else
          xdg-open "$file" >/dev/null 2>&1 || {
            echo "No editor available to open '$file'" >&2
            return 1
          }
        fi
        ;;
    esac
  else
    # Editor binary not found; fallback to xdg-open if possible
    if command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$file" >/dev/null 2>&1 || true
    else
      echo "No editor or xdg-open available to open '$file'" >&2
      return 1
    fi
  fi
  notify_info "Opened: $(basename "$file")"
  return 0
}

# Prompt for path to create a new file (and open it)
create_new_file() {
  local path
  path="$(choose 'New file path (absolute or relative to $HOME)')"
  [ -z "$path" ] && return 1
  # Expand ~ to $HOME
  path="${path/#\~/$HOME}"
  # If relative, interpret relative to $HOME
  if [[ "$path" != /* ]]; then
    path="$HOME/$path"
  fi
  mkdir -p "$(dirname "$path")"
  touch "$path"
  chmod --reference="$HOME/.config" "$path" 2>/dev/null || true
  open_in_editor "$path"
  return 0
}

# Search files across all registered categories (fzf preferred)
search_files() {
  local root_paths
  local candidate
  root_paths=()
  for k in "${!CATEGORIES[@]}"; do
    root_paths+=("${CATEGORIES[$k]}")
  done

  # Build find command across all categories
  local find_cmd
  find_cmd=(find)
  for p in "${root_paths[@]}"; do
    [ -d "$p" ] && find_cmd+=("$p")
  done
  find_cmd+=( -type f -not -path '*/.git/*' )

  if command -v fzf >/dev/null 2>&1; then
    candidate="$( "${find_cmd[@]}" 2>/dev/null | fzf --prompt 'Search configs> ' --height 40% )"
  elif command -v rofi >/dev/null 2>&1; then
    candidate="$( "${find_cmd[@]}" 2>/dev/null | rofi -dmenu -i -p 'Search configs' )"
  else
    candidate="$( "${find_cmd[@]}" 2>/dev/null | sort | choose 'Search picks' )"
  fi

  if [ -n "$candidate" ]; then
    open_in_editor "$candidate"
    return 0
  fi
  return 1
}

# Open a directory in file manager or list it
open_directory() {
  local dir="$1"
  [ -z "$dir" ] && return 1
  if [ -d "$dir" ]; then
    if command -v thunar >/dev/null 2>&1; then
      thunar "$dir" >/dev/null 2>&1 &
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$dir" >/dev/null 2>&1 &
    else
      notify_info "Directory: $dir"
    fi
    return 0
  fi
  return 1
}

# -------------------------
# Main flow
# -------------------------
main_menu() {
  local keys=()
  for key in "${!CATEGORIES[@]}"; do
    keys+=("$key")
  done
  # Sort keys for predictable ordering
  IFS=$'\n' sorted_keys=($(sort <<<"${keys[*]}"))
  unset IFS

  # Compose menu with extra actions
  menu_items=()
  menu_items+=("Search (fzf/rofi)")
  menu_items+=("New file...")
  menu_items+=("Open directory...")
  menu_items+=("Exit")
  for k in "${sorted_keys[@]}"; do
    menu_items+=("$k")
  done

  local choice
  choice="$(printf '%s\n' "${menu_items[@]}" | choose 'QuickEdit — choose source or action')"
  [ -z "$choice" ] && exit 0

  case "$choice" in
    "Exit") exit 0 ;;
    "New file...")
      create_new_file
      exit 0
      ;;
    "Search (fzf/rofi)")
      search_files
      exit 0
      ;;
    "Open directory...")
      # Ask which category to open directory from
      local cat
      cat="$(printf '%s\n' "${sorted_keys[@]}" | choose 'Open directory: choose category')"
      [ -z "$cat" ] && exit 0
      open_directory "${CATEGORIES[$cat]}"
      exit 0
      ;;
    *)
      # A category was picked
      if [ -n "${CATEGORIES[$choice]:-}" ]; then
        local base="${CATEGORIES[$choice]}"
        if [ -f "$base" ]; then
          # Single file (e.g., starship.toml)
          open_in_editor "$base"
          exit 0
        fi

        if [ ! -d "$base" ]; then
          notify_info "Not found: $base"
          exit 1
        fi

        # Build file list
        mapfile -t files < <(list_files_in "$base" 2>/dev/null)
        if [ "${#files[@]}" -eq 0 ]; then
          notify_info "No files found inside: $base"
          exit 1
        fi

        local pick
        # Prepend options
        local file_menu=( "Create new file..." "Open directory..." "" )
        file_menu+=( "${files[@]}" )
        pick="$(printf '%s\n' "${file_menu[@]}" | choose "Files in ${choice}")"

        [ -z "$pick" ] && exit 0

        case "$pick" in
          "Create new file...")
            create_new_file
            exit 0
            ;;
          "Open directory...")
            open_directory "$base"
            exit 0
            ;;
          "")
            exit 0
            ;;
          *)
            # Selected a file (relative path)
            local fullpath="$base/$pick"
            # If the selected path doesn't exist, ask to create it
            if [ ! -f "$fullpath" ]; then
              if printf '%s\n' "Yes" "No" | choose "File does not exist. Create?"; then
                mkdir -p "$(dirname "$fullpath")"
                touch "$fullpath"
              else
                exit 0
              fi
            fi
            open_in_editor "$fullpath"
            exit 0
            ;;
        esac
      fi
      ;;
  esac
}

# Run main
main_menu

exit 0
