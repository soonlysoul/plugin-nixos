# Flake posé par « nixconf adopter » autour de la configuration reprise de
# /etc/nixos. Il ne change rien à ce qu'elle déclare : il l'enveloppe, et
# épingle nixpkgs dans flake.lock au lieu de le laisser au canal.
{
  description = "Configuration NixOS du poste « @HOTE@ »";

  inputs = {
    # Le canal du système installé. Pour monter de version : remplacer par le
    # canal suivant, lire ses notes de version, puis construire AVANT d'appliquer.
    # system.stateVersion, dans configuration.nix, ne change JAMAIS.
    nixpkgs.url = "github:NixOS/nixpkgs/@CANAL@";
  };

  outputs =
    { nixpkgs, ... }@inputs:
    {
      # ⚠ L'évaluation demande --impure : configuration.nix importe la
      # description matérielle par son emplacement système
      # (/etc/nixos/hardware-configuration.nix), qui n'entre jamais dans le dépôt.
      nixosConfigurations."@HOTE@" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs; };
        modules = [
          ./configuration.nix
          # Une description matérielle ancienne ne porte pas toujours
          # l'architecture : celle de ce poste, à défaut.
          { nixpkgs.hostPlatform = nixpkgs.lib.mkDefault "@SYSTEME@"; }
        ];
      };
    };
}
