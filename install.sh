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

VELA_DIR="$HOME/.vela"
mkdir -p "$VELA_DIR"

install_aura() { ensure_aura; }

aur() { install_aura; aura "$@"; }

sync_repo() {
  local name="$1" url="$2" dest="$VELA_DIR/$name"
  if [ -d "$dest/.git" ]; then (cd "$dest" && git pull --rebase --autostash || true); else git clone "$url" "$dest"; fi
}

link_config() {
  local src="$1" dest="$2"; mkdir -p "$(dirname "$dest")"
  if [ -e "$dest" ] || [ -L "$dest" ]; then confirm "Replace $(basename "$dest")?" && rm -rf "$dest" || return; fi
  ln -s "$src" "$dest"
}

install_core() { title "Installing Core"; sync_repo shell https://github.com/vela-dots/shell.git; sync_repo cli https://github.com/vela-dots/cli.git; info "Core synced into $VELA_DIR"; }
install_cli()  { title "Installing CLI";  sync_repo cli https://github.com/vela-dots/cli.git; (cd "$VELA_DIR/cli" && cargo build --release --manifest-path cli/Cargo.toml || true); info "CLI built (if Rust toolchain available)."; }
install_shell(){ title "Installing Shell";sync_repo shell https://github.com/vela-dots/shell.git; info "Shell synced. Configure Hyprland to launch Quickshell Vela."; }

install_codium_extension() {
  title "Installing Codium + extension"
  install_aura
  need codium || aura -S vscodium-bin
  sync_repo codium https://github.com/vela-dots/codium.git
  info "Open $VELA_DIR/codium in VSCodium to build/install extension."
}

install_settings_app() { title "Installing Settings app"; sync_repo settings https://github.com/vela-dots/settings.git; (cd "$VELA_DIR/settings" && cargo build --release || true); info "Settings app built."; }

setup_symlinks() {
  title "Set up config symlinks"
  local choices=("Hypr -> ~/.config/hypr" "Fuzzel -> ~/.config/fuzzel" "Btop -> ~/.config/btop" "Helix -> ~/.config/helix" "VSCodium theme")
  local picks; picks=$(printf '%s\n' "${choices[@]}" | multi) || return 0
  while IFS= read -r p; do
    case "$p" in
      Hypr*)    link_config "$VELA_DIR/shell/config/hypr"                      "$HOME/.config/hypr" ;;
      Fuzzel*)  link_config "$VELA_DIR/cli/src/vela/data/templates/fuzzel.ini" "$HOME/.config/fuzzel/fuzzel.ini" ;;
      Btop*)    link_config "$VELA_DIR/cli/src/vela/data/templates/btop.theme" "$HOME/.config/btop/themes/vela.theme" ;;
      Helix*)   link_config "$VELA_DIR/cli/src/vela/data/templates/helix.toml" "$HOME/.config/helix/themes/vela.toml" ;;
      VSCodium*) info "Run: vela editor theme to generate VSCodium theme" ;;
    esac
  done <<< "$picks"
}

apply_themes() { title "Apply themes"; need vela && vela editor theme || true; info "Themes refreshed."; }

# Shell refresh: add NVM init, Cargo bin to PATH
configure_shell_refresh() {
  title "Configuring shell refresh"
  local line1='export NVM_DIR="$HOME/.nvm"'
  local line2='[ -s "/usr/share/nvm/init-nvm.sh" ] && . "/usr/share/nvm/init-nvm.sh" # load nvm'
  local line3='export PATH="$HOME/.cargo/bin:$PATH"'
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    [ -f "$rc" ] || continue
    grep -q "init-nvm.sh" "$rc" || printf '\n%s\n%s\n' "$line1" "$line2" >> "$rc"
    grep -q 'cargo/bin' "$rc" || printf '\n%s\n' "$line3" >> "$rc"
  done
  info "Appended NVM and Cargo PATH to ~/.bashrc and ~/.zshrc when present."
}

# NVM + Node LTS via Aura
install_nvm_and_lts() {
  title "Installing NVM + Node LTS"
  aura -S nvm
  export NVM_DIR="$HOME/.nvm"
  [ -s "/usr/share/nvm/init-nvm.sh" ] && . "/usr/share/nvm/init-nvm.sh" || true
  [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" || true
  nvm install --lts || true
  nvm use --lts || true
  configure_shell_refresh
}

codium_ext() { need codium || install_codium_extension; codium --install-extension "$1" || true; }

# Languages
install_svelte()     { install_nvm_and_lts; codium_ext svelte.svelte-vscode; codium_ext dbaeumer.vscode-eslint; codium_ext esbenp.prettier-vscode; }
install_python()     { aura -S python python-pip python-virtualenv; codium_ext ms-python.python; codium_ext ms-python.vscode-pylance; codium_ext ms-toolsai.jupyter; }
install_lua()        { aura -S lua luarocks; codium_ext sumneko.lua || codium_ext luals.lua || true; }
install_rust()       { aura -R rust || true; aura -S rustup; rustup default stable || true; codium_ext rust-lang.rust-analyzer; codium_ext serayuzgur.crates; codium_ext vadimcn.vscode-lldb; configure_shell_refresh; }
install_astro()      { install_nvm_and_lts; codium_ext astro-build.astro-vscode; codium_ext esbenp.prettier-vscode; }
install_ts()         { install_nvm_and_lts; codium_ext dbaeumer.vscode-eslint; codium_ext esbenp.prettier-vscode; }
install_js()         { install_nvm_and_lts; codium_ext dbaeumer.vscode-eslint; codium_ext esbenp.prettier-vscode; }
install_tailwind()   { install_nvm_and_lts; codium_ext bradlc.vscode-tailwindcss; codium_ext esbenp.prettier-vscode; }

# Designer accent override
write_override() { local p="$1" s="$2" t="$3"; local d="${XDG_STATE_HOME:-$HOME/.local/state}/vela"; mkdir -p "$d"; echo "{\"activeLanguage\":\"designer\",\"colors\":{\"primary\":\"$p\",\"secondary\":\"$s\",\"tertiary\":\"$t\",\"surfaceTint\":\"$p\"}}" > "$d/palette_override.json"; }

preset_core()      { install_core; install_cli; install_shell; setup_symlinks; apply_themes; info "Core preset completed."; }
preset_developer() { install_core; install_cli; install_shell; install_codium_extension; setup_symlinks; title "Optional: detect project languages"; local path; path=$(input "Project path (blank skip)") || true; [ -n "${path:-}" ] && [ -d "$path" ] && need vela && vela editor detect -p "$path" || true; apply_themes; info "Developer preset completed."; }
preset_designer()  { install_core; install_cli; install_shell; setup_symlinks; local app=""; for c in figma-linux inkscape gimp krita blender; do command -v "$c" &>/dev/null && { app="$c"; break; }; done; case "$app" in figma-linux) write_override ff7262 1e1e1e 2f80ed;; inkscape) write_override 0a84ff 1e8b60 7e57c2;; gimp) write_override 5a9ece 8e44ad e67e22;; krita) write_override 3daee9 d08770 a3be8c;; blender) write_override f5792a 5e81ac 81a1c1;; *) write_override ff3e00 312e81 1f2937;; esac; info "Designer preset wrote palette override; toggle accents in tray to enable."; apply_themes; info "Designer preset completed."; }

preset_custom() {
  gum style --border normal --margin "1 2" --padding "1 2" --border-foreground 212 "Vela Installer"
  local modules; modules=$(printf '%s\n' \
    "Install Core" \
    "Install CLI" \
    "Install Shell" \
    "Install Codium Extension" \
    "Install Settings App" \
    "Setup Config Symlinks" \
    "Apply Themes" \
    | multi) || exit 0
  while IFS= read -r m; do case "$m" in "Install Core") install_core;; "Install CLI") install_cli;; "Install Shell") install_shell;; "Install Codium Extension") install_codium_extension;; "Install Settings App") install_settings_app;; "Setup Config Symlinks") setup_symlinks;; "Apply Themes") apply_themes;; esac; done <<< "$modules"
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
  local preset; preset=$(choose Core Developer Designer Custom) | sed 's/\r$//' || exit 0
  case "$preset" in Core) preset_core;; Developer) preset_developer;; Designer) preset_designer;; Custom) preset_custom;; esac
  confirm "Install programming languages / extensions?" && languages_menu || true
}

presets_menu

