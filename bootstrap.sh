#!/bin/bash

machineType="$(uname -s)"
echo "==> Step 0: For linux virtual machine, create local bind to avoid /nix folder"
if [ "$machineType" = 'Linux' ]; then
  # /nix has to live on the home disk: VMs reset the boot
  # disk when the machine is assigned to a user. No sudo for the mkdir, this is
  # our own home directory. The chown happens after Step 1 instead, since the
  # installer would only re-root the store paths it creates.
  mkdir -p ~/.nix-store
  if [ ! -d "/nix/store" ]; then
    sudo mkdir -p /nix
    sudo mount --bind "$HOME/.nix-store" /nix
  fi
fi

echo "==> Step 1: Install Nix via Determinate if missing"
if ! command -v nix &> /dev/null; then
  # On Linux this is deliberately a single-user install (see nix.conf for why):
  # `--init none` skips the nix-daemon service, which would otherwise be the one
  # part of Nix living on the boot disk and would be deleted on re-assignment.
  # macOS has no such reset, so nix-darwin gets the normal multi-user install.
  if [ "$machineType" = 'Linux' ]; then
    installerArgs=(install linux --no-confirm --init none)
  else
    installerArgs=(install --no-confirm)
  fi
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- "${installerArgs[@]}"

  # `--init none` leaves Nix root-only, so hand /nix to this user to finish the
  # single-user install. Do it here while the store is still nearly empty --
  # the same chown against a warm store takes minutes.
  if [ "$machineType" = 'Linux' ]; then
    sudo chown -R "$(id -un):$(id -gn)" /nix
  fi

  # The installer wires Nix into new shells, but this script is still running
  # in the shell that started before Nix existed. Source the profile now so
  # `nix` works for the rest of this run instead of needing a second session.
  # The profile script isn't written to be `set -u` safe, so relax that guard
  # just around the source. It sets no NIX_REMOTE, so it is fine single-user.
  : "${NIX_DAEMON_PROFILE:=/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh}"
  if [ -f "$NIX_DAEMON_PROFILE" ]; then
    set +u
    # shellcheck disable=SC1090
    . "$NIX_DAEMON_PROFILE"
    set -u
  fi
fi

echo "==> Step 2: Setup git if needed"
SSH_KEY_PATH=~/".ssh/id_ed25519"

if [ ! -f "$SSH_KEY_PATH" ]; then
  git config --global user.name "Wenjie Zhou"
  git config --global user.email "caigaa@gmail.com"
  # use "https" instead of "git", https://github.blog/2021-09-01-improving-git-protocol-security-github/
  git config --global url."https://github.com/".insteadOf git://github.com/

  ssh-keygen -t ed25519 -C "caigaa@gmail.com"
  ssh-add --apple-use-keychain ~/.ssh/id_ed25519

  [ -z "$pathToPub" ] && pathToPub=$HOME/.ssh/id_ed25519.pub
  checkLinux xclip -sel clip < $pathToPub
  checkMac pbcopy < $pathToPub
  echo "Public key copied to clipboard, please add to git, then we will check status. If this fails script exits."
  read -p "Press any key to continue... " -n1 -s
  ssh -T git@github.com
  if [ $? -eq 255 ]; then
    echo "Failed to connect to git"
    exit 1
  fi
fi

echo "==> Step 3: symlink this repo to ~/.dotfiles"
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles, so this
# has to exist before the first switch or the build will fail to find them.
ln -sfn "$DIR" ~/.dotfiles

echo "==> Step 4: check user name setup"
# Do this before any sudo call: sudo resets $USER to root, so whoami has to
# run as the real interactive user first.
REAL_USER="$(whoami)"
USER_STRING="user"
if [ $machineType == 'Darwin' ]; then
  USER_STRING="mac_user"
else
  USER_STRING="ubuntu_user"
fi
FLAKE_USER="$(sed -nE "s/^[[:space:]]*${USER_STRING} = \"([^\"]+)\";.*/\1/p" "$DIR/flake.nix" | head -n1)"
if [ -z "$FLAKE_USER" ]; then
    echo "    Could not find the single \"$USER_STRING = \" line in flake.nix."
    echo "    Edit flake.nix yourself before continuing."
    exit 1
elif [ "$FLAKE_USER" != "$REAL_USER" ]; then
  echo "    flake.nix is configured for user \"$FLAKE_USER\", but you are \"$REAL_USER\"."
  read -r -p "    Rewrite flake.nix's \"$USER_STRING = \" line to \"$REAL_USER\"? [y/N] " REPLY
  if [ "$REPLY" = "y" ] || [ "$REPLY" = "Y" ]; then
    sed -i '' -E "s/^([[:space:]]*$USER_STRING = \")[^\"]+(\";.*)/\1${REAL_USER}\2/" "$DIR/flake.nix"
    echo "    Updated. Review the change with: git diff flake.nix"
  else
    echo "    Skipped. Edit the single \"$USER_STRING = \" line in flake.nix yourself before continuing."
    exit 1
  fi
else
  echo "    flake.nix already matches \"$REAL_USER\", nothing to do."
fi

echo "==> Step 5: first nix-rebuild switch"

if [ $machineType == 'Darwin' ]; then
  # darwin-rebuild doesn't exist yet on a fresh machine, so run it straight
  # from the flake this once. After this, rebuild.sh works normally.
  # This fetches the darwin-rebuild tool from the nix-darwin-26.05 release branch,
  # not the exact flake.lock revision. The system config it applies is still pinned
  # by this repo's flake.lock.
  # sudo resets PATH to a secure default that excludes /nix/.../bin, so a
  # freshly installed `nix` would not be found under sudo even though it's
  # on PATH here. Resolve the absolute path first and invoke that instead.
  NIX_BIN="$(command -v nix)"
  # "mac" is the flake host label - if you renamed it, change it in flake.nix
  # and rebuild.sh too.
  sudo "$NIX_BIN" run github:nix-darwin/nix-darwin/nix-darwin-26.05#darwin-rebuild -- \
    switch --flake ~/.dotfiles#mac
  # If this still fails with "nix: command not found", open a new terminal
  # (Determinate adds nix to new shells' PATH) and re-run ./bootstrap.sh.
elif [ "$machineType" = 'Linux' ]; then
  # Nothing special to do for the first switch on Linux, and rebuild.sh already
  # links ~/.config/nix/nix.conf and finds `nix` when it is off PATH. Deferring
  # to it keeps that setup in one place.
  bash "$DIR/rebuild.sh"
else
  echo "Unsupported OS \"$machineType\", only Linux and Darwin are supported" >&2
  exit 1
fi

echo "==> Done. Use ./rebuild.sh for future changes."
