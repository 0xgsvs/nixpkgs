{
  stdenv,
  fetchFromGitHub,
  fetchCrate,
  lib,
  rustPlatform,
  udev,
  protobuf,
  installShellFiles,
  pkg-config,
  openssl,
  nix-update-script,
  versionCheckHook,
  clang,
  libclang,
  rocksdb,
  # Taken from https://github.com/anza-xyz/agave/blob/master/scripts/cargo-install-all.sh#L84
  # https://github.com/anza-xyz/agave/blob/master/scripts/agave-build-lists.sh
  solanaPkgs ? [
    # AGAVE_BINS_END_USER
    "agave-install"
    "solana"
    # "solana-keygen"
    # AGAVE_BINS_DEV
    # "solana-test-validator"
    # AGAVE_BINS_VAL_OP
    # "agave-validator"
    # "agave-watchtower"
    # "solana-gossip"
    # "solana-faucet"
    # AGAVE_BINS_DEPRECATED (will be removed in the future)
    # "solana-stake-accounts"
    # "solana-tokens"
    # "agave-install-init"
    # AGAVE_BINS_DCOU (DEV_CONTEXT_ONLY_UTILS)
    # "agave-ledger-tool"
    # "solana-bench-tps"
  ]
  ++ [
    # XXX: Ensure `solana-genesis` is built LAST!
    # See https://github.com/solana-labs/solana/issues/5826
    # "solana-genesis"
  ],
}:
let
  version = "4.0.0-beta.7";

  src = fetchFromGitHub {
    owner = "anza-xyz";
    repo = "agave";
    tag = "v${version}";
    hash = "sha256-UAk9glAfcZ20ze9HvZ7N0p7vTUqYgB/q0Z5MDWl4nMM=";
  };

  commonEnv = {
    RUSTFLAGS = "-Amismatched_lifetime_syntaxes -Adead_code -Aunused_parens -Aunused_imports -Ainteger_to_ptr_transmutes -Aunused_unsafe";
    LIBCLANG_PATH = "${libclang.lib}/lib";

    # Used by build.rs in the rocksdb-sys crate. If we don't set these, it would
    # try to build RocksDB from source.
    ROCKSDB_LIB_DIR = "${rocksdb}/lib";

    # Require this on darwin otherwise the compiler starts rambling about missing
    # cmath functions
    CPPFLAGS = lib.optionalString stdenv.hostPlatform.isDarwin "-isystem ${lib.getInclude stdenv.cc.libcxx}/include/c++/v1";
    LDFLAGS = lib.optionalString stdenv.hostPlatform.isDarwin "-L${lib.getLib stdenv.cc.libcxx}/lib";

    # If set, always finds OpenSSL in the system, even if the vendored feature is enabled.
    OPENSSL_NO_VENDOR = 1;
  };

  commonArgs = {
    strictDeps = true;
    doCheck = false;
    env = commonEnv;
    nativeBuildInputs = [
      protobuf
      pkg-config
    ];
    buildInputs = [
      openssl
      clang
      libclang
      rustPlatform.bindgenHook
    ]
    ++ lib.optionals stdenv.hostPlatform.isLinux [ udev ];
  };

  spl-token = rustPlatform.buildRustPackage (
    commonArgs
    // {
      pname = "spl-token";
      version = "5.5.0";
      src = fetchCrate {
        pname = "spl-token-cli";
        version = "5.5.0";
        hash = "sha256-XRcDStuNijexsdinMFhYvNcnpyvD0zyZIOm6OpgwjuA=";
      };
      cargoHash = "sha256-DlX7fW9qZlBTU9boXZ5++E45I/+GdqX6dnogmYjTrsk=";
    }
  );

  # These are now independent crates.io packages (detached from agave in PR #10584).
  # The version is independent from agave's version - 4.0.0 was published to crates.io
  cargo-build-sbf = rustPlatform.buildRustPackage (
    commonArgs
    // {
      pname = "cargo-build-sbf";
      version = "4.0.0";
      src = fetchCrate {
        pname = "cargo-build-sbf";
        version = "4.0.0";
        hash = "sha256-pxXFbXnrM5YNgRzKjJx45akG+zc1XS4sD4y93UFVxY8=";
      };
      cargoHash = "sha256-slsf1qmCdUsXYORwPbtvZuWSh60T7GaJ1mVk+JZliPs=";
    }
  );

  cargo-test-sbf = rustPlatform.buildRustPackage (
    commonArgs
    // {
      pname = "cargo-test-sbf";
      version = "4.0.0";
      src = fetchCrate {
        pname = "cargo-test-sbf";
        version = "4.0.0";
        hash = "sha256-t0iTMCfwCC5tXZ8OH8i9FfpdWKf9NK/3DkoZXCJsvfk=";
      };
      cargoHash = "sha256-ZBTW3T9MdRaU/ziI46AHYbhLcHGO3R135ctt/+HuHOY=";
    }
  );
in

rustPlatform.buildRustPackage (
  commonArgs
  // {
    pname = "solana-cli";
    inherit version src;

    cargoHash = "sha256-8yLaN633941DGoni7Rt6Xv10o+YiJ8ATaMrGj9LJXLY=";

    cargoBuildFlags = map (n: "--bin=${n}") solanaPkgs;

    nativeBuildInputs = [ installShellFiles ] ++ commonArgs.nativeBuildInputs;

    doInstallCheck = true;
    nativeInstallCheckInputs = [ versionCheckHook ];
    versionCheckProgram = "${placeholder "out"}/bin/solana";

    postInstall = lib.optionalString (stdenv.buildPlatform.canExecute stdenv.hostPlatform) ''
      # installShellCompletion --cmd solana \
      #   --bash <($out/bin/solana completion --shell bash) \
      #   --fish <($out/bin/solana completion --shell fish)

      cp ${cargo-build-sbf}/bin/cargo-build-sbf $out/bin/
      cp ${cargo-test-sbf}/bin/cargo-test-sbf $out/bin/
      cp ${spl-token}/bin/spl-token $out/bin/

      # mkdir -p $out/bin/deps
      # find . -name libsolana_program.dylib -exec cp {} $out/bin/deps \;
      # find . -name libsolana_program.rlib -exec cp {} $out/bin/deps \;
    '';

    meta = {
      description = "Web-Scale Blockchain for fast, secure, scalable, decentralized apps and marketplaces";
      homepage = "https://solana.com";
      changelog = "https://github.com/anza-xyz/agave/blob/v4.0.0-beta.7/CHANGELOG.md";
      license = lib.licenses.asl20;
      maintainers = with lib.maintainers; [
        netfox
        happysalada
        aikooo7
        JacoMalan1
        _0xgsvs
      ];
      platforms = lib.platforms.unix;
    };

    passthru.updateScript = nix-update-script { };
  }
)
