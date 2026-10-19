#!/usr/bin/env bash

set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# home.nix resolves its mkOutOfStoreSymlink paths through ~/.dotfiles.
ln -sfn "$DIR" ~/.dotfiles

machineType="$(uname -s)"
if [ "$machineType" = 'Linux' ]; then
  # Virtual VMs re-run /opt/setup.sh when the machine is assigned to
  # a user, which resets the boot disk. Nix itself lives on the home disk and
  # survives, but the bind mount and everything Nix put outside $HOME does not,
  # so restore all of it here before trying to build. See nix.conf for why this
  # is a single-user install.
  if [ ! -d "/nix/store" ]; then
    echo "Restoring /nix mount from ~/.nix-store"
    sudo mkdir -p /nix
    sudo mount --bind "$HOME/.nix-store" /nix
    # Deliberately no chown: ~/.nix-store is already owned by this user and the
    # bind mount carries that through, so re-chowning 6k store paths would cost
    # minutes and change nothing.
  fi

  # The installer wrote experimental-features to /etc/nix/nix.conf, which the
  # reset deletes. Keep the real config in this repo and point Nix at it.
  # Not named NIX_CONF_DIR: that is a Nix variable that would point Nix at the
  # *system* config if it ever got exported.
  nixConfDir="${XDG_CONFIG_HOME:-$HOME/.config}/nix"
  mkdir -p "$nixConfDir"
  ln -sfn "$DIR/nix.conf" "$nixConfDir/nix.conf"

  # /etc/profile.d/nix.sh is reset away too, so `nix` can be missing from PATH
  # in a fresh shell even though it is installed. home.nix puts it back for
  # interactive shells; this covers the run that applies that home.nix.
  if ! command -v nix >/dev/null 2>&1; then
    PATH="/nix/var/nix/profiles/default/bin:$PATH"
  fi

  # "ubuntu" is the homeConfigurations attribute in flake.nix - keep in sync.
  # home-manager is pinned to the same release branch as the flake input so the
  # CLI and the evaluated modules cannot drift apart.
  exec nix run github:nix-community/home-manager/release-26.05 -- \
    switch --flake ~/.dotfiles#ubuntu
elif [ "$machineType" = 'Darwin' ]; then
  # "mac" is the darwinConfigurations attribute in flake.nix - keep in sync.
  exec sudo darwin-rebuild switch --flake ~/.dotfiles#mac
else
  echo "Unsupported OS \"$machineType\", only Linux and Darwin are supported" >&2
  exit 1
fi
