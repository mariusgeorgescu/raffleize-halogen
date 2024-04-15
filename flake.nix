{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    purs-nix.url = "github:mariusgeorgescu/purs-nix";
    ps-tools.follows = "purs-nix/ps-tools";
    ctl.url = "github:Plutonomicon/cardano-transaction-lib/v7.0.0";
    utils.url = "github:ursi/flake-utils";
    ctl-nix.url = "github:LovelaceAcademy/ctl-nix";
    npmlock2nix.url = "github:nix-community/npmlock2nix";
    npmlock2nix.flake = false;
    # script.url = "github:LovelaceAcademy/nix-templa/tes/change-cache?dir=iogx-plutus";
  };

  outputs = { self, utils, ... }@inputs:
    let
      # TODO add missing arm to match standard systems
      #  right now purs-nix is only compatible with x86_64-linux
      systems = [ "x86_64-linux" "x86_64-darwin" ];
      overlays = with inputs.ctl.overlays; [
        # adds easy-ps for CTL
        purescript
        # adds:
        #  plutip-server
        #  ogmios
        #  kupo
        runtime
      ];
    in utils.apply-systems { inherit inputs systems overlays; }
    ({ system, pkgs, ... }@ctx:
        let 
          inherit (pkgs) nodejs;
          # TODO Use a default purs version from CTL
          inherit (ctx.ps-tools.for-0_15)
            purescript purs-tidy purescript-language-server;
          purs = pkgs.easy-ps.purs-0_15_0;
          purs-nix = inputs.purs-nix {
            inherit system;
            overlays = [ ctx.ctl-nix ];
          };
          npmlock2nix = import inputs.npmlock2nix { inherit pkgs; };
          node_modules = npmlock2nix.v1.node_modules { src = ./.; } + /node_modules;
          ps = purs-nix.purs
            {
              purescript = purs;
              # Project dir (src, test)
              dir = ./.;
              # Dependencies
              dependencies =
                with purs-nix.ps-pkgs;
                [
                  cardano-transaction-lib
                  halogen
                ];
              # FFI dependencies
              # TODO Affjax FFI should be in ctl-nix
              foreign.Affjax.node_modules = node_modules;
            };
          prebuilt = (pkgs.arion.build {
            inherit pkgs;
            modules = [ (pkgs.buildCtlRuntime { }) ];
          }).outPath;
          runtime = pkgs.writeShellApplication {
            name = "runtime";
            runtimeInputs = [ pkgs.arion pkgs.docker ];
            text = ''arion --prebuilt-file ${prebuilt} "$@"'';
          };
          cardano-cli = pkgs.writeShellApplication {
            name = "cardano-cli";
            runtimeInputs = with pkgs; [ docker ];
            text = ''
              docker volume inspect store_node-preview-ipc || _warn "Cardano node volume not found, run \"dev or runtime\" first."
              docker run --rm -it -v "$(pwd)":/data -w /data -v store_node-preview-ipc:/ipc -e CARDANO_NODE_SOCKET_PATH=/ipc/node.socket --entrypoint cardano-cli "inputoutput/cardano-node" "$@"
            '';
          };
          ps-command = ps.command { };
          purs-watch = pkgs.writeShellApplication {
            name = "purs-watch";
            runtimeInputs = with pkgs; [ entr ps-command ];
            text = "find src | entr -s 'echo building && purs-nix compile'";
          };
          webpack = pkgs.writeShellApplication {
            name = "webpack";
            runtimeInputs = with pkgs; [ nodejs ];
            text = ''npx webpack "$@"'';
          };
          serve = pkgs.writeShellApplication {
            name = "serve";
            runtimeInputs = with pkgs; [ webpack ];
            text = ''BROWSER_RUNTIME=1 webpack serve --progress --open "$@"'';
          };
          dev = pkgs.writeShellApplication {
            name = "dev";
            runtimeInputs = with pkgs; [
              concurrently
              runtime
              purs-watch
              serve
            ];
            text = ''
              concurrently\
                --color "auto"\
                --prefix "[{command}]"\
                --handle-input\
                --restart-tries 10\
                purs-watch\
                serve\
                "runtime up"
            '';
          };
          bundle = pkgs.writeShellApplication {
            name = "bundle";
            runtimeInputs = with pkgs; [ webpack ];
            text = ''BROWSER_RUNTIME=1 webpack --mode=production "$@"'';
          };
          docs = pkgs.writeShellApplication {
            name = "docs";
            runtimeInputs = with pkgs; [ nodejs ps-command ];
            text = ''purs-nix docs && npx http-server ./generated-docs/html -o'';
          };
        in
        {
          packages.default = ps.output { };

          devShells.default =
            pkgs.mkShell
              {
                packages =
                  with pkgs;
                  [
                    runtime
                    cardano-cli
                    easy-ps.purescript-language-server
                    purs
                    ps-command
                    purs-watch
                    webpack
                    serve
                    dev
                    bundle
                    docs
                  ];
                shellHook = ''
                  alias log_='printf "\033[1;32m%s\033[0m\n" "$@"'
                  alias info_='printf "\033[1;34m[INFO] %s\033[0m\n" "$@"'
                  alias warn_='printf "\033[1;33m[WARN] %s\033[0m\n" "$@"'
                  log_ "Welcome to ctl-full shell."
                  info_ "Available commands: runtime, cardano-cli, webpack, purs-nix, serve, dev, bundle, docs."
                  info_ "testnet-magic for preview is 2"
                '';
              };
        });

  # --- Flake Local Nix Configuration ----------------------------
  nixConfig = {
    extra-experimental-features = "nix-command flakes";
    # This sets the flake to use nix cache.
    # Nix should ask for permission before using it,
    # but remove it here if you do not want it to.
    extra-substituters = [
      "https://cache.tcp4.me?priority=99"
      "https://cache.iog.io"
      "https://cache.zw3rk.com"
      "https://hercules-ci.cachix.org"
      "https://klarkc.cachix.org"
    ];
    extra-trusted-public-keys = [
      "cache.tcp4.me:cmk2Iz81lQuX7FtTUcBgtqgI70E8p6SOamNAIcFDSew="
      "hydra.iohk.io:f/Ea+s+dFdN+3Y/G+FDgSq+a5NEWhJGzdjvKNGv0/EQ="
      "loony-tools:pr9m4BkM/5/eSTZlkQyRt57Jz7OMBxNSUiMC4FkcNfk="
      "hercules-ci.cachix.org-1:ZZeDl9Va+xe9j+KqdzoBZMFJHVQ42Uu/c/1/KMC5Lw0="
      "klarkc.cachix.org-1:R+z+m4Cq0hMgfZ7AQ42WRpGuHJumLLx3k0XhwpNFq9U="
    ];
  };
}
