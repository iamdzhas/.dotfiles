#!/usr/bin/env bash
# Sets up zsh, tmux and Neovim (LazyVim) from this repo on a Debian/Ubuntu machine.
# Usage on a fresh server:
#   sudo apt update && sudo apt install -y git && \
#     git clone https://github.com/iamdzhas/.dotfiles ~/.dotfiles && ~/.dotfiles/install.sh
set -euo pipefail

# The repo can live anywhere: paths are taken from the script's own location.
DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"

# Run as root without sudo installed, or as a regular user with sudo.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi

echo "==> Update packages..."
$SUDO apt-get update

echo "==> Install dependencies..."
# build-essential: compiler for nvim-treesitter parsers
# unzip, python3-venv: needed by Mason to install LSP servers and tools (e.g. ruff)
DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y \
  zsh curl git ripgrep fd-find nodejs npm tmux build-essential unzip python3-venv

echo "==> Zsh -> default shell..."
ZSH_BIN="$(command -v zsh)"
CURRENT_SHELL="$(getent passwd "$(id -un)" | cut -d: -f7)"
if [ "$CURRENT_SHELL" != "$ZSH_BIN" ]; then
  # sudo: plain chsh asks for the user's password, which key-only servers often lack
  $SUDO chsh -s "$ZSH_BIN" "$(id -un)"
fi

echo "==> Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
  sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
fi

echo "==> Zsh plugins..."
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
  git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
  git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi

echo "==> Starship..."
if ! command -v starship >/dev/null; then
  curl -fsSL https://starship.rs/install.sh | sh -s -- --yes
fi

echo "==> Neovim..."
# Official release archive: works without snap and is always a recent version.
case "$(uname -m)" in
  x86_64) NVIM_ARCH="x86_64" ;;
  aarch64 | arm64) NVIM_ARCH="arm64" ;;
  *) echo "Unsupported architecture for Neovim: $(uname -m)" >&2; exit 1 ;;
esac
if [ ! -x "$HOME/.local/nvim/bin/nvim" ]; then
  NVIM_TMP="$(mktemp -d)"
  curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${NVIM_ARCH}.tar.gz" |
    tar -xz -C "$NVIM_TMP"
  rm -rf "$HOME/.local/nvim"
  mkdir -p "$HOME/.local"
  mv "$NVIM_TMP/nvim-linux-${NVIM_ARCH}" "$HOME/.local/nvim"
  rm -rf "$NVIM_TMP"
fi
mkdir -p "$LOCAL_BIN"
ln -sf "$HOME/.local/nvim/bin/nvim" "$LOCAL_BIN/nvim"

echo "==> Symlinks..."
ln -sf "$DOTFILES/zsh/.zshrc" "$HOME/.zshrc"
ln -sf "$DOTFILES/tmux/.tmux.conf" "$HOME/.tmux.conf"
mkdir -p "$HOME/.config"
# Keep an existing nvim config as a backup instead of deleting it.
if [ -e "$HOME/.config/nvim" ] && [ ! -L "$HOME/.config/nvim" ]; then
  BACKUP="$HOME/.config/nvim.bak.$(date +%Y%m%d%H%M%S)"
  mv "$HOME/.config/nvim" "$BACKUP"
  echo "    Existing ~/.config/nvim moved to $BACKUP"
fi
ln -sfn "$DOTFILES/nvim" "$HOME/.config/nvim"

echo "==> Fd alias..."
if command -v fdfind >/dev/null; then
  ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
fi

echo "==> TPM and tmux plugins..."
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
  git clone https://github.com/tmux-plugins/tpm "$HOME/.tmux/plugins/tpm"
fi
# Installs the plugins listed in .tmux.conf (same as prefix+I inside tmux).
"$HOME/.tmux/plugins/tpm/bin/install_plugins"

echo "==> Neovim plugins and language servers..."
# Done here so the first nvim launch is ready to use. Network hiccups only warn:
# whatever is missing gets installed on the next nvim launch.
"$LOCAL_BIN/nvim" --headless "+Lazy! sync" +qa ||
  echo "    WARNING: some LazyVim plugins failed to install; open nvim to retry."
"$LOCAL_BIN/nvim" --headless "+lua require('mason')" \
  "+MasonInstall pyright ruff lua-language-server tree-sitter-cli" +qa ||
  echo "    WARNING: some Mason tools failed to install; run :Mason in nvim to retry."

echo "==> Version checks..."
NODE_MAJOR="$(node -v | sed 's/^v//; s/\..*//')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "    WARNING: Node $(node -v) is too old for some LazyVim tools (pyright). Install Node 18+ (e.g. via nvm)."
fi
TMUX_VERSION="$(tmux -V | grep -oE '[0-9]+\.[0-9]+' | head -1)"
if [ "$(printf '%s\n' 3.2 "$TMUX_VERSION" | sort -V | head -1)" != "3.2" ]; then
  echo "    WARNING: tmux $TMUX_VERSION is older than 3.2; some bindings in .tmux.conf will fail."
fi

echo ""
echo "✓ Ready! Log out and back in (or run zsh) to start using zsh."
echo "  At the first launch nvim installs LazyVim plugins automatically."
