{
  lib,
  flake-parts-lib,
  neovim-lib,
  ...
}:
with lib; let
  inherit (builtins) typeOf;
  inherit (flake-parts-lib) mkPerSystemOption;
  inherit (neovim-lib) toLua;

  lazySpec = with types; {
    options = {
      src = mkOption {
        type = nullOr (oneOf [attrs path]);
        default = null;
      };
      package = mkOption {
        type = nullOr package;
        default = null;
      };
      name = mkOption {
        type = nullOr str;
        default = null;
      };
      lazy = mkOption {
        type = nullOr bool;
        default = null;
      };
      dependencies = mkOption {
        type = listOf (oneOf [attrs str]);
        default = [];
      };
      config = mkOption {
        type = nullOr (oneOf [attrs bool path]);
        default = null;
      };
      opts = mkOption {
        type = attrs;
        default = {};
      };
      event = mkOption {
        type = nullOr (oneOf [str (listOf str)]);
        default = null;
      };
      ft = mkOption {
        type = nullOr (oneOf [str (listOf str)]);
        default = null;
      };
      keys = mkOption {
        type = nullOr (oneOf [str (listOf str)]);
        default = null;
      };
      priority = mkOption {
        type = nullOr int;
        default = null;
      };
    };
  };
in {
  options = {
    perSystem = mkPerSystemOption ({
      config,
      pkgs,
      ...
    }: let
      cfg = config.neovim.lazy;
    in {
      options = with types; {
        neovim = {
          lazy = {
            opts = {
              dev = {
                path = mkOption {
                  type = nullOr (oneOf [path str]);
                  default = null;
                };
              };
              install = {
                missing = mkOption {
                  type = bool;
                  default = false;
                };
              };
            };
            plugins = mkOption {
              type = attrsOf (submodule lazySpec);
              default = {};
            };
          };

          build = {
            lazy = {
              spec = mkOption {
                type = str;
                internal = true;
              };
              opts = mkOption {
                type = str;
                internal = true;
              };
            };
          };
        };
      };

      config = mkIf (cfg.plugins != []) {
        neovim.build = let
          inherit (config.neovim) build;
          inherit (pkgs.vimUtils) buildVimPluginFrom2Nix;

          plugins = mapAttrs (name: attrs:
            if attrs.package != null
            then attrs.package
            else
              buildVimPluginFrom2Nix {
                inherit name;
                inherit (attrs) src;
              })
          cfg.plugins;
        in {
          lazy = let
            toPlugin' = name: attrs: let
              package = plugins."${name}";
            in
              {
                inherit name;
                dir = "${package}";
              }
              // optionalAttrs (attrs.lazy != null) {inherit (attrs) lazy;}
              // optionalAttrs (attrs.dependencies != []) {
                dependencies = map (dep:
                  if builtins.isAttrs dep
                  then {
                    inherit (dep) name;
                    dir = "${dep.src}";
                  }
                  else {
                    name = dep;
                    dir = toString plugins."${dep}";
                  })
                attrs.dependencies;
              }
              // optionalAttrs (typeOf attrs.config == "bool") {
                inherit (attrs) config;
              }
              // optionalAttrs (builtins.isAttrs attrs.config) {
                config = true;
                opts = attrs.config;
              }
              // optionalAttrs ((typeOf attrs.config) == "path") {
                config = _: ''dofile "${attrs.config}"'';
              }
              // optionalAttrs (attrs.event != null) {inherit (attrs) event;}
              // optionalAttrs (attrs.ft != null) {inherit (attrs) ft;}
              // optionalAttrs (attrs.keys != null) {inherit (attrs) keys;}
              // optionalAttrs (attrs.priority != null) {inherit (attrs) priority;};

            spec = toLua (mapAttrsToList toPlugin' cfg.plugins);
            opts = toLua (cfg.opts // {performance.rtp.reset = false;});
          in {
            inherit spec opts;
          };

          plugins' = attrValues plugins;
          plugins =
            pkgs.runCommand "plugins.lua" {
              nativeBuildInputs = with pkgs; [stylua];
              passAsFile = ["text"];
              preferLocalBuild = true;
              allowSubstitutes = false;
              text = ''
                -- Generated by Nix (via github:willruggiano/neovim.nix)
                vim.opt.rtp:prepend "${pkgs.vimPlugins.lazy-nvim}"
                require("lazy").setup(${build.lazy.spec}, ${build.lazy.opts})
              '';
            } ''
              target=$out
              mkdir -p "$(dirname "$target")"
              if [ -e "$textPath" ]; then
                mv "$textPath" "$target"
              else
                echo -n "$text" > "$target"
              fi

              stylua --config-path ${../../stylua.toml} $target
            '';
        };
      };
    });
  };
}
