############################################################################
#
# Cardano Wallet Nix build
#
# Derivation attributes of this file can be build with "nix-build -A ..."
# Discover attribute names using tab-completion in your shell.
#
# Interesting top-level attributes:
#
#   - cardano-wallet - cli executable
#   - tests - attrset of test-suite executables
#     - cardano-wallet-core.unit
#     - cardano-wallet.integration
#     - etc (layout is PACKAGE.COMPONENT)
#   - checks - attrset of test-suite results
#     - cardano-wallet-core.unit
#     - cardano-wallet.integration
#     - etc
#   - benchmarks - attret of benchmark executables
#     - cardano-wallet-core.db
#     - cardano-wallet.latency
#     - etc
#   - migration-tests - tests db migrations from previous versions
#   - dockerImage - tarballs of the docker images
#     - shelley
#   - shell - import of shell.nix
#   - project.hsPkgs - a Haskell.nix package set of all packages and their dependencies
#     - cardano-wallet-core.components.library
#     - etc (layout is PACKAGE-NAME.components.COMPONENT-TYPE.COMPONENT-NAME)
#
# The attributes of this file are imported by the Hydra jobset and
# mapped into the layout TARGET-SYSTEM.ATTR-PATH.BUILD-SYSTEM.
# See release.nix for more info about that.
#
# Other documentation:
#   https://github.com/input-output-hk/cardano-wallet/wiki/Building#nix-build
#
############################################################################

{ system ? builtins.currentSystem
, crossSystem ? null
, config ? {}
# Import pinned Nixpkgs with iohk-nix and Haskell.nix overlays
, pkgs ? import ./nix/default.nix { inherit system crossSystem config sourcesOverride; }
# Use this git revision for stamping executables
, gitrev ? pkgs.commonLib.commitIdFromGitRepoOrZero ./.git
# Use this to reference local sources rather than the niv pinned versions (see nix/default.nix)
, sourcesOverride ? {}
# GitHub PR number (as a string), set when building a Hydra PR jobset.
, pr ? null
# Bors job type (as a string), set when building a Hydra bors jobset.
, borsBuild ? null
}:

let
  # The project sources. Sources are filtered by filename, and then
  # further filtered by package subdirectory.
  src = lib.cleanSourceWith {
    src = pkgs.haskell-nix.cleanSourceHaskell { src = ./.; };
    name = "cardano-wallet-src";
    filter = commonLib.removeSocketFilesFilter;
  };

  buildHaskellProject = args: import ./nix/haskell.nix ({
    inherit config pkgs;
    inherit (pkgs) buildPackages lib stdenv haskell-nix;
    inherit src gitrev pr borsBuild;
  } // args);
  project = buildHaskellProject {};
  profiledProject = buildHaskellProject { profiling = true; };
  coveredProject = buildHaskellProject { coverage = true; };

  # Functions used in this file
  inherit (pkgs) lib commonLib;
  inherit (pkgs.haskell-nix.haskellLib)
    selectProjectPackages
    isProjectPackage
    collectComponents
    collectChecks;
  getPackageChecks = lib.mapAttrs (_: package: package.checks);

  self = {
    inherit pkgs commonLib src project profiledProject coveredProject;
    inherit (project.hsPkgs.cardano-wallet-core.identifier) version;
    # Cardano
    inherit (project.hsPkgs.cardano-cli.components.exes) cardano-cli;
    cardano-node = project.hsPkgs.cardano-node.components.exes.cardano-node // {
      deployments = pkgs.cardano-node-deployments;
    };
    # expose db-converter, so daedalus can ship it without needing to pin a ouroborus-network rev
    inherit (project.hsPkgs.ouroboros-consensus-byron.components.exes) db-converter;
    # adrestia tool belt
    inherit (project.hsPkgs.bech32.components.exes) bech32;
    inherit (project.hsPkgs.cardano-addresses-cli.components.exes) cardano-address;
    inherit (project.hsPkgs.cardano-transactions.components.exes) cardano-tx;

    # The main executable
    cardano-wallet = import ./nix/package-cardano-node.nix {
      inherit pkgs gitrev;
      haskellBuildUtils = pkgs.haskellBuildUtils.package;
      exe = project.hsPkgs.cardano-wallet.components.exes.cardano-wallet;
      inherit (self) cardano-node;
    };

    # Local test cluster and mock metadata server
    inherit (project.hsPkgs.cardano-wallet.components.exes)
      local-cluster
      mock-token-metadata-server;

    # `tests` are the test suites which have been built.
    tests = collectComponents "tests" isProjectPackage coveredProject.hsPkgs;
    # `checks` are the result of executing the tests.
    checks = pkgs.recurseIntoAttrs (getPackageChecks (selectProjectPackages coveredProject.hsPkgs));
    # Combined project coverage report
    testCoverageReport = coveredProject.projectCoverageReport;
    # `benchmarks` are only built, not run.
    benchmarks = collectComponents "benchmarks" isProjectPackage project.hsPkgs;

    dockerImage = let
      mkDockerImage = backend: exe: pkgs.callPackage ./nix/docker.nix { inherit backend exe; };
    in pkgs.recurseIntoAttrs (lib.mapAttrs mkDockerImage {
      shelley = self.cardano-wallet;
    });

    shell = import ./shell.nix { inherit pkgs; walletPackages = self; };
    shell-prof = import ./shell.nix { inherit pkgs; walletPackages = self; profiling = true; };
    cabalShell = import ./nix/cabal-shell.nix { inherit pkgs; walletPackages = self; };
    stackShell = import ./nix/stack-shell.nix { inherit pkgs; walletPackages = self; };

    # This is the ./nix/regenerate.sh script. Put it here so that it's
    # built and cached on CI.
    inherit (pkgs) stackNixRegenerate;
  };

in
  self
