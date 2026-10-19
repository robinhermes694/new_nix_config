
# Automatically restore /nix mount if missing after VM reset
if [ ! -d "/nix/store" ]; then
    echo "Re-mounting persistent Nix store..."
    sudo mkdir -p /nix
    sudo mount --bind "$HOME/.nix-store" /nix
fi
