{
  description = "air-eater - Hyprland-style dynamic workspaces on a fixed macOS Space pool";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
    }:
    flake-utils.lib.eachSystem [ "aarch64-darwin" ] (
      system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        # AIDEV-NOTE: Swift コンパイラと SDK は Nix から入れず、システムの
        # Command Line Tools / Xcode のものを使う。nixpkgs の swift は 5.10 止まりで、
        # AppKit / Carbon / ApplicationServices も macOS 26 の SDK で引きたいため。
        # mkShell (stdenv) は SDKROOT と DEVELOPER_DIR を Nix の apple-sdk に向けて
        # xcrun swift を壊すので、mkShellNoCC を使う。
        # swift-format も Swift 6 同梱の `swift format` を使い、nixpkgs 版 (5.10) は入れない。
        treefmtEval = treefmt-nix.lib.evalModule pkgs {
          projectRootFile = "flake.nix";
          programs.nixfmt.enable = true;
          settings.formatter.swift-format = {
            command = "swift";
            options = [
              "format"
              "--in-place"
              "--parallel"
            ];
            includes = [ "*.swift" ];
          };
        };
      in
      {
        formatter = treefmtEval.config.build.wrapper;

        devShells.default = pkgs.mkShellNoCC {
          packages = [
            pkgs.swiftlint
            pkgs.just
            treefmtEval.config.build.wrapper
          ];

          # nixpkgs の swiftlint は sourcekitdInProc を dlopen するが、既定の探索先は
          # Xcode.app 前提で Command Line Tools だけの環境では見つからない。
          # TOOLCHAIN_DIR で選択中のツールチェーンを明示する
          shellHook = ''

            developer_dir="$(xcode-select -p)"
            if [ -d "$developer_dir/Toolchains/XcodeDefault.xctoolchain" ]; then
              export TOOLCHAIN_DIR="$developer_dir/Toolchains/XcodeDefault.xctoolchain"
            else
              export TOOLCHAIN_DIR="$developer_dir"
            fi

            echo "air-eater dev environment ($(swift --version 2>/dev/null | head -1))"
            echo "Commands: just build, just test, just lint, just fmt, just run"
          '';
        };
      }
    );
}
