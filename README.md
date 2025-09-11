Vela Installer
==============

Interactive installer for Vela dotfiles, powered by gum.

Quick install
-------------

curl:

    curl -fsSL https://raw.githubusercontent.com/vela-dots/vela/main/install.sh | bash

wget:

    wget -qO- https://raw.githubusercontent.com/vela-dots/vela/main/install.sh | bash

Usage
-----

    ./install.sh

It guides you through selecting a preset (Core, Developer, Designer, Custom), sets up config symlinks, installs languages/tooling, and applies themes.

Requirements
------------

- gum (https://github.com/charmbracelet/gum)
- git

Presets
-------
- Core: minimal required shell + CLI with color customization.
- Developer: Core + language-detected coloring (via Codium extension), plus Node LTS via NVM.
- Designer: Core + design-app detected accent override (expands color handling).
- Custom: full menu of installable modules and symlink choices.
