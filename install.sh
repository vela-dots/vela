#!/usr/bin/env bash
set -euo pipefail

# Vela Installer - gum presets + language setup, Aura-only

need() { command -v "$1" &>/dev/null; }

# Preflight: ensure Aura, gum, git
ensure_aura() {
  need aura && return 0
  echo "Installing Aura (AUR helper) via makepkg -si"
  tmp="$(mktemp -d)"; pushd "$tmp" >/dev/null
  git clone https://aur.archlinux.org/aura-bin.git
  cd aura-bin
  makepkg -si
  popd >/dev/null; rm -rf "$tmp"
}

ensure_gum() {
  need gum && return 0
  ensure_aura
  aura -S gum || aura -S gum-bin
}

ensure_git() {
  need git && return 0
  ensure_aura
  aura -S git
}

ensure_gum
ensure_git

# Now gum is available
title()   { gum style --bold --foreground 212 "$1"; }
info()    { gum format --theme dracula "$1"; }
confirm() { gum confirm --prompt.foreground 212 "$1"; }
choose()  { gum choose "$@"; }
multi()   { gum choose --no-limit "$@"; }
input()   { gum input --placeholder "$1"; }

# Short pause so Y/N prompts are visible and interactable
pause_for_prompt() { sleep 0.7; }

VELA_DIR="$HOME/.vela"
mkdir -p "$VELA_DIR"

install_aura() { ensure_aura; }

aur() { install_aura; pause_for_prompt; aura "$@"; }

sync_repo() {
  # Be safe under `set -u` (nounset) and force a clean, up-to-date checkout
  local name="${1-}" url="${2-}"
  if [ -z "${name:-}" ] || [ -z "${url:-}" ]; then
    info "sync_repo: missing arguments (name, url); skipping"
    return 1
  fi
  local dest="$VELA_DIR/$name"
  if [ -d "$dest/.git" ]; then
    (
      cd "$dest"
      git fetch --all --prune --tags || true
      # For cli, preserve local changes (e.g., Rust installer) and skip hard reset
      local keep_local=0
      if [ "$name" = "cli" ] && ! git diff --quiet; then keep_local=1; fi
      if [ $keep_local -eq 0 ]; then
        # Determine default branch and hard reset to remote head
        local def
        def=$(git remote show origin 2>/dev/null | awk '/HEAD branch:/ {print $NF}')
        if [ -n "${def:-}" ]; then
          git reset --hard "origin/$def" || true
        else
          local cur
          cur=$(git symbolic-ref --short -q HEAD || echo main)
          git reset --hard "origin/$cur" || git reset --hard origin/HEAD || true
        fi
        git clean -fdx || true
      else
        info "cli repo has local changes; preserving them (no hard reset)"
      fi
      git submodule update --init --recursive || true
    )
  else
    git clone --recurse-submodules "$url" "$dest"
  fi
}

link_config() {
  local src="$1" dest="$2"; mkdir -p "$(dirname "$dest")"
  # Force-replace existing links or directories
  [ -e "$dest" ] || [ -L "$dest" ] && rm -rf "$dest"
  ln -s "$src" "$dest"
}

# Remove Python sources from local Vela repos (we use Rust/QML only)
purge_python_sources() {
  title "Removing Python sources from Vela repos"
  # Remove Python scripts
  find "$VELA_DIR" -type f -name '*.py' -not -path '*/.git/*' -print -delete || true
  # Remove common Python packaging files
  find "$VELA_DIR" \( -name 'pyproject.toml' -o -name 'setup.py' -o -name 'requirements.txt' -o -name 'Pipfile' -o -name 'poetry.lock' \) \
    -not -path '*/.git/*' -print -delete || true
  # Remove __pycache__
  find "$VELA_DIR" -type d -name '__pycache__' -not -path '*/.git/*' -print -exec rm -rf {} + 2>/dev/null || true
  # Remove old Python package tree if still present
  [ -d "$VELA_DIR/cli/src/vela" ] && rm -rf "$VELA_DIR/cli/src/vela"
  # Remove any pipx virtualenv that could shadow the Rust CLI
  rm -rf "$HOME/.local/share/pipx/venvs/vela-cli" 2>/dev/null || true
}
# Remove old user configs under ~/.config that belong to Vela
purge_vela_configs() {
  title "Removing old Vela configs"
  rm -rf "$HOME/.config/quickshell/vela" \
         "$HOME/.config/quickshell"/vela.backup-* \
         "$HOME/.config/vela" 2>/dev/null || true
  info "Removed ~/.config/quickshell/vela*, ~/.config/vela (if present)."
}

# Install fresh user config under ~/.config/vela
# No JSON config: deploy QML directly into QuickShell config
deploy_shell_qml() {
  title "Deploying shell QML to QuickShell config"
  local src="$VELA_DIR/shell" dest="$HOME/.config/quickshell/vela"
  mkdir -p "$dest"
  # Copy only QML and required assets (images/fonts/icons); keep dirs structure
  rsync -a --delete \
    --include '*/' \
    --include '*.qml' \
    --include '*.js' \
    --include '*.png' --include '*.jpg' --include '*.jpeg' --include '*.webp' --include '*.gif' \
    --include '*.svg' \
    --include '*.ttf' --include '*.otf' --include '*.woff' --include '*.woff2' \
    --exclude '*' \
    --exclude '.git/' --exclude 'plugin/' --exclude 'CMakeLists.txt' --exclude 'MIGRATION_TO_RUST.md' \
    "$src/" "$dest/"
  # Strip unsupported pragma-env lines from all QML files
  if command -v rg >/dev/null 2>&1; then
    rg -l --hidden --no-ignore -S -g '!**/.git/**' "^\s*(//\s*)?@?\s*pragma\s+(env|Env)\b.*" "$dest" | xargs -r sed -i -E '/^\s*(\/\/\s*)?@?\s*pragma\s+(env|Env)\b.*/d'
  else
    find "$dest" -type f -name '*.qml' -print0 | xargs -0 sed -i -E '/^\s*(\/\/\s*)?@?\s*pragma\s+(env|Env)\b.*/d'
  fi
  info "Copied QML to ~/.config/quickshell/vela."
}

install_core() { title "Installing Core"; sync_repo shell https://github.com/vela-dots/shell.git; sync_repo cli https://github.com/vela-dots/cli.git; purge_python_sources; info "Core synced into $VELA_DIR"; }
install_cli()  {
  title "Installing CLI"
  sync_repo cli https://github.com/vela-dots/cli.git
  purge_python_sources
  (
    cd "$VELA_DIR/cli" && \
    if [ -f Cargo.toml ]; then cargo clean || true; cargo build --release; \
    elif [ -f cli/Cargo.toml ]; then cargo clean || true; cargo build --release --manifest-path cli/Cargo.toml; \
    else echo "No Cargo.toml; skipping build"; fi
  ) || true
  mkdir -p "$HOME/.local/bin"
  # Replace any existing pipx shim or old binary
  [ -e "$HOME/.local/bin/vela" ] && rm -f "$HOME/.local/bin/vela"
  if [ -x "$VELA_DIR/cli/target/release/vela" ]; then
    install -m 0755 "$VELA_DIR/cli/target/release/vela" "$HOME/.local/bin/vela" || cp "$VELA_DIR/cli/target/release/vela" "$HOME/.local/bin/vela"
  fi
  # Remove Python pipx venv if present
  [ -d "$HOME/.local/share/pipx/venvs/vela-cli" ] && rm -rf "$HOME/.local/share/pipx/venvs/vela-cli" || true
  info "CLI built and installed to ~/.local/bin/vela (Rust)."
}
install_shell(){
  title "Installing Shell (Rust installer)"
  sync_repo shell https://github.com/vela-dots/shell.git
  purge_vela_configs
  # Always use the local Rust CLI (with installer subcommand)
  (cd "$VELA_DIR/cli" && cargo build --release) || true
  "$VELA_DIR/cli/target/release/vela" install shell --purge --src "$VELA_DIR/shell" --dest "$HOME/.config/quickshell/vela"
  info "Shell installed to ~/.config/quickshell/vela (Rust)."
}

install_code_extension() {
  title "Installing Code + extension"
  install_aura
  need code || { pause_for_prompt; aura -S code || aura -S code-bin; }
  sync_repo codium https://github.com/vela-dots/codium.git
  info "Open $VELA_DIR/codium in VS Code to build/install extension."
}

install_settings_app() { title "Installing Settings app"; sync_repo settings https://github.com/vela-dots/settings.git; (cd "$VELA_DIR/settings" && cargo clean || true; cargo build --release || true); info "Settings app built."; }

# Desktop portals, DBus broker, and notifier
install_portals() {
  title "Installing desktop portals + notifier"
  pause_for_prompt; aur -S xdg-desktop-portal xdg-desktop-portal-hyprland dbus-broker mako || true
  info "Enabling user services (dbus-broker, xdg-desktop-portal, xdg-desktop-portal-hyprland, mako)"
  # Make sure the user systemd is ready
  systemctl --user daemon-reload >/dev/null 2>&1 || true
  systemctl --user enable --now dbus-broker.service >/dev/null 2>&1 || true
  systemctl --user enable --now xdg-desktop-portal.service >/dev/null 2>&1 || true
  systemctl --user enable --now xdg-desktop-portal-hyprland.service >/dev/null 2>&1 || true
  systemctl --user enable --now mako.service >/dev/null 2>&1 || true
  info "Portals + notifier enabled for this session and future logins."
}

setup_symlinks() {
  title "Set up config symlinks"
  local choices=("Hypr -> ~/.config/hypr" "Fuzzel -> ~/.config/fuzzel" "Btop -> ~/.config/btop" "Helix -> ~/.config/helix" "VS Code theme")
  local picks; picks=$(printf '%s\n' "${choices[@]}" | multi) || return 0
  while IFS= read -r p; do
    case "$p" in
      Hypr*)    link_config "$VELA_DIR/shell/config/hypr"                      "$HOME/.config/hypr" ;;
      Fuzzel*)  link_config "$VELA_DIR/cli/assets/templates/fuzzel.ini" "$HOME/.config/fuzzel/fuzzel.ini" ;;
      Btop*)    link_config "$VELA_DIR/cli/assets/templates/btop.theme" "$HOME/.config/btop/themes/vela.theme" ;;
      Helix*)   link_config "$VELA_DIR/cli/assets/templates/helix.toml" "$HOME/.config/helix/themes/vela.toml" ;;
      VS\ Code*) info "Run: vela colors write-defaults (VS Code theme generation handled separately)" ;;
    esac
  done <<< "$picks"
}

apply_themes() { title "Apply themes"; info "QML copied; no JSON themes to apply."; }

# Shell refresh: add NVM init, Cargo bin to PATH
configure_shell_refresh() {
  title "Configuring shell refresh"
  local line1='export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.nvm}"'
  local line2='[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"  # loads nvm'
  local line3='export PATH="$HOME/.cargo/bin:$PATH"'
  for rc in "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    sed -i '/\/usr\/share\/nvm\/init-nvm\.sh/d' "$rc" 2>/dev/null || true
    sed -i '/export NVM_DIR="\$HOME\/\.nvm"/d' "$rc" 2>/dev/null || true
    if ! grep -qE 'NVM_DIR=.*(XDG_CONFIG_HOME|\.nvm)' "$rc"; then
      printf '\n%s\n%s\n' "$line1" "$line2" >> "$rc"
    fi
    grep -q 'cargo/bin' "$rc" || printf '\n%s\n' "$line3" >> "$rc"
  done
  info "Ensured zshrc sets NVM_DIR and loads nvm; added Cargo PATH."
}

# NVM + Node LTS via Aura
install_nvm_and_lts() {
  title "Installing NVM + Node LTS"
  if ! command -v nvm >/dev/null 2>&1; then
    local tmp_script; tmp_script="$(mktemp)"
    if curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh -o "$tmp_script"; then
      bash "$tmp_script" || true
    else
      info "Failed to download nvm installer; check your network and try again."
    fi
    rm -f "$tmp_script"
  fi
  export NVM_DIR="${XDG_CONFIG_HOME:-$HOME/.nvm}"
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || true
  if command -v nvm >/dev/null 2>&1; then
    # Temporarily disable nounset around nvm (it is not -u safe)
    case $- in *u*) __had_u=1;; *) __had_u=0;; esac
    set +u
    nvm install --lts || true
    nvm use --lts || true
    [ "$__had_u" = 1 ] && set -u
  else
    info "nvm not found in this shell. After install, open a new shell or 'source ~/.zshrc', then run: nvm install --lts"
  fi
  configure_shell_refresh
}

code_ext() { need code || install_code_extension; code --uninstall-extension "$1" >/dev/null 2>&1 || true; code --install-extension "$1" --force || true; }

# Try a list of possible extension IDs (handles Code vs Code - OSS/Open VSX differences)
code_ext_try() {
  need code || install_code_extension
  local id
  for id in "$@"; do
    if code --install-extension "$id" --force >/dev/null 2>&1; then
      info "Installed extension: $id"
      return 0
    fi
  done
  info "Failed to install any of: $* (check marketplace availability)"
  return 1
}

# Ensure we don't install both rust-lang.rust and rust-analyzer; prefer the main Rust extension
ensure_rust_vscode_ext() {
  need code || install_code_extension
  # Uninstall analyzer first to avoid conflicts
  code --uninstall-extension rust-lang.rust-analyzer >/dev/null 2>&1 || true
  # Install the main Rust extension; if unavailable (Open VSX), fall back to analyzer but ensure only one is present
  if ! code --install-extension rust-lang.rust --force >/dev/null 2>&1; then
    info "rust-lang.rust not available; falling back to rust-analyzer"
    code --uninstall-extension rust-lang.rust >/dev/null 2>&1 || true
    code --install-extension rust-lang.rust-analyzer --force >/dev/null 2>&1 || true
  fi
}

# Languages
install_svelte()     { install_nvm_and_lts; code_ext svelte.svelte-vscode; code_ext dbaeumer.vscode-eslint; code_ext esbenp.prettier-vscode; }
install_python()     { pause_for_prompt; aura -S python python-pip python-virtualenv; code_ext ms-python.python; code_ext_try ms-python.vscode-pylance basedpyright.vscode-pyright ms-pyright.pyright; code_ext ms-toolsai.jupyter; }
install_lua()        { pause_for_prompt; aura -S lua luarocks; code_ext_try sumneko.lua luals.lua lua-language-server.lua || true; }
install_rust()       { pause_for_prompt; aura -R rust || true; aura -S rustup; rustup default stable || true; ensure_rust_vscode_ext; code_ext serayuzgur.crates; code_ext vadimcn.vscode-lldb; configure_shell_refresh; }
install_astro()      { install_nvm_and_lts; code_ext astro-build.astro-vscode; code_ext esbenp.prettier-vscode; }
install_ts()         { install_nvm_and_lts; code_ext dbaeumer.vscode-eslint; code_ext esbenp.prettier-vscode; }
install_js()         { install_nvm_and_lts; code_ext dbaeumer.vscode-eslint; code_ext esbenp.prettier-vscode; }
install_tailwind()   { install_nvm_and_lts; code_ext bradlc.vscode-tailwindcss; code_ext esbenp.prettier-vscode; }

# Designer accent override
write_override() { local p="$1" s="$2" t="$3"; local d="${XDG_STATE_HOME:-$HOME/.local/state}/vela"; mkdir -p "$d"; echo "{\"activeLanguage\":\"designer\",\"colors\":{\"primary\":\"$p\",\"secondary\":\"$s\",\"tertiary\":\"$t\",\"surfaceTint\":\"$p\"}}" > "$d/palette_override.json"; }

preset_core()      { install_core; install_cli; install_shell; setup_symlinks; apply_themes; info "Core preset completed."; }
preset_developer() { install_core; install_cli; install_shell; install_code_extension; setup_symlinks; title "Optional: detect project languages"; local path; path=$(input "Project path (blank skip)") || true; [ -n "${path:-}" ] && [ -d "$path" ] && need vela && vela editor detect -p "$path" || true; apply_themes; info "Developer preset completed."; }
preset_designer()  { install_core; install_cli; install_shell; setup_symlinks; local app=""; for c in figma-linux inkscape gimp krita blender; do command -v "$c" &>/devnull && { app="$c"; break; }; done; case "$app" in figma-linux) write_override ff7262 1e1e1e 2f80ed;; inkscape) write_override 0a84ff 1e8b60 7e57c2;; gimp) write_override 5a9ece 8e44ad e67e22;; krita) write_override 3daee9 d08770 a3be8c;; blender) write_override f5792a 5e81ac 81a1c1;; *) write_override ff3e00 312e81 1f2937;; esac; info "Designer preset wrote palette override; toggle accents in tray to enable."; apply_themes; info "Designer preset completed."; }

preset_everything() {
  title "Installing Everything"
  install_core
  install_cli
  install_shell
  install_portals
  install_code_extension
  install_settings_app
  setup_symlinks
  apply_themes
  info "Everything preset completed."
}

preset_custom() {
  gum style --border normal --margin "1 2" --padding "1 2" --border-foreground 212 "Vela Installer"
  local modules; modules=$(printf '%s\n' \
    "Install Core" \
    "Install CLI" \
    "Install Shell" \
    "Install Code Extension" \
    "Install Settings App" \
    "Setup Config Symlinks" \
    "Apply Themes" \
    | multi) || exit 0
  while IFS= read -r m; do case "$m" in "Install Core") install_core;; "Install CLI") install_cli;; "Install Shell") install_shell;; "Install Code Extension") install_code_extension;; "Install Settings App") install_settings_app;; "Setup Config Symlinks") setup_symlinks;; "Apply Themes") apply_themes;; esac; done <<< "$modules"
  info "Custom preset completed."
}

languages_menu() {
  title "Language Setup"
  local langs; langs=$(printf '%s\n' \
    "Svelte" "Python" "Lua" "Rust" "Astro" "TypeScript" "JavaScript" "TailwindCSS" "Install NVM + Node LTS only" | multi) || return 0
  while IFS= read -r l; do case "$l" in Svelte) install_svelte;; Python) install_python;; Lua) install_lua;; Rust) install_rust;; Astro) install_astro;; TypeScript) install_ts;; JavaScript) install_js;; TailwindCSS) install_tailwind;; *LTS*) install_nvm_and_lts;; esac; done <<< "$langs"
}

presets_menu() {
  title "Select a preset"
  local preset=""
  if ! preset=$(choose Everything Core Developer Designer Custom | sed 's/\r$//'); then
    exit 0
  fi
  [ -z "${preset:-}" ] && exit 0
  case "$preset" in Everything) preset_everything;; Core) preset_core;; Developer) preset_developer;; Designer) preset_designer;; Custom) preset_custom;; esac
  confirm "Install programming languages / extensions?" && languages_menu || true
}

# CLI entry: allow non-interactive --all
case "${1-}" in
  --all|-a|everything|Everything)
    preset_everything
    confirm "Install programming languages / extensions?" && languages_menu || true
    ;;
  *)
    presets_menu
    ;;
esac
