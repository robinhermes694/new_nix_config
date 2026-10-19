{
  description = "dotfiles managed by nix";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=26.05";
    # Use `github:nix-darwin/nix-darwin/nix-darwin-26.05` to use Nixpkgs 26.05.
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";

    # Add the official Herdr input
    herdr.url = "github:herdrdev/herdr";
    herdr.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = inputs@{ self, nix-darwin, herdr, nix-homebrew, home-manager, nixpkgs }:
    let
      mac_user = "TBD";
      ubuntu_user = "wenjie.zhou";
    in
    {
      # 1. macOS system configuration
      darwinConfigurations."mac" = nix-darwin.lib.darwinSystem {
        specialArgs = { user = mac_user; };
        modules = [
          ./mac_config.nix
          nix-homebrew.darwinModules.nix-homebrew
          home-manager.darwinModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "backup";
            home-manager.extraSpecialArgs = {
              user = mac_user;
              inherit inputs;
            };
            home-manager.users.${mac_user} = import ./home.nix;
          }
        ];
      };

      # 2. Remote Ubuntu Configuration (Standalone Home Manager)
      homeConfigurations."ubuntu" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = {
          user = ubuntu_user;
          inherit inputs;
        };
        modules = [
          ./home.nix
        ];
      };
    };
}
