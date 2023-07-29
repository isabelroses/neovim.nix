{
  lib,
  flake-parts-lib,
  ...
}: let
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (lib) mkOption types;

  mkInitLua = {
    config,
    pkgs,
  }:
    pkgs.writeTextFile {
      name = "init.lua";
      text = ''
        -- Generated by Nix (via github:willruggiano/neovim.nix)
        vim.cmd.source "${config.neovim.build.before}"
        vim.cmd.source "${config.neovim.build.plugins}"
      '';
    };
in {
  options = {
    perSystem = mkPerSystemOption ({
      inputs',
      config,
      pkgs,
      ...
    }: {
      options = with types; {
        neovim = {
          package = mkOption {
            type = package;
            description = "The Neovim derivation to use";
            inherit (inputs'.neovim.packages) default;
          };

          build = {
            before = mkOption {
              internal = true;
              type = package;
            };

            initlua = mkOption {
              internal = true;
              type = package;
            };

            rplugin = mkOption {
              internal = true;
              type = package;
            };
          };
        };
      };

      config = let
        env = pkgs.buildEnv {
          name = "neovim-host-prog";
          paths =
            [pkgs.nodePackages.neovim]
            ++ [(pkgs.python3.withPackages (ps: with ps; [pynvim]))];
        };
      in {
        neovim.build.before = pkgs.writeTextFile {
          name = "before.lua";
          text = ''
            -- Generated by Nix (via github:willruggiano/neovim.nix)
            vim.g.node_host_prog = "${env}/bin/neovim-node-host"
            vim.g.python3_host_prog = "${env}/bin/python"
          '';
        };

        neovim.build.initlua = mkInitLua {
          inherit config pkgs;
        };

        neovim.build.rplugin = with lib;
          pkgs.runCommand "rplugin.vim" {
            nativeBuildInputs = [config.neovim.package];
          } ''
            mkdir $out
            export HOME=$TMP
            export NVIM_RPLUGIN_MANIFEST=$out/rplugin.vim
            export PATH="$PATH:${makeBinPath (unique config.neovim.paths)}"
            nvim --headless -i NONE -n -u ${config.neovim.build.initlua} +UpdateRemotePlugins +quit!
          '';
      };
    });
  };
}
