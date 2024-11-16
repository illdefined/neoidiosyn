{ lib, pkgs, ... }: { ... }@attrs: let
  stdenv' = attrs.stdenv or attrs.baseStdenv;
  pkgs' = attrs.pkgs or attrs.buildPackages;

  inherit (pkgs') stdenv;
  inherit (stdenv) buildPlatform hostPlatform targetPlatform;
  inherit (stdenv.cc) isClang nativePrefix targetPrefix;
  inherit (stdenv.cc.bintools) isLLVM;

  inherit (lib) optionals toList filterAttrs mapAttrs;
in pkgs.addAttrsToDerivation (prevAttrs: let
  autoVarInit = prevAttrs.autoVarInit or null;
  boundsCheck = prevAttrs.boundsCheck or false;
  overrideAlloc = prevAttrs.overrideAlloc or true;  

  env = {
    NIX_CFLAGS_COMPILE = [ "-pipe" "-fno-semantic-interposition" ]
      ++ optionals isClang [ "-ffp-contract=fast-honor-pragmas" ]
      ++ optionals isLLVM [ "-flto" ]
      ++ optionals (autoVarInit != null) [ "-ftrivial-auto-var-init=${autoVarInit}" ]
      ++ optionals boundsCheck [ "-fsanitize-trap=bounds,object-size,vla-bound" ];

    NIX_CFLAGS_LINK = isClang [ "--ld-path=${lib.getExe' stdenv.cc.bintools (targetPrefix + "ld")}" ];

    NIX_LDFLAGS = [ "-O2" "--hash-style=gnu" ]
      ++ optionals isLLVM [ "--icf=safe" "--lto-O2" ]
      ++ optionals overrideAlloc [ "-lmimalloc" ];

    NIX_RUSTFLAGS = [ "-C" "opt-level=2" "-C" "target-cpu=${targetPlatform.gcc.arch}" ]
      ++ optionals isLLVM [ "-C" "lto" "-C" "linker-plugin-lto" ]
      ++ (map (flag: [ "-C" "link-arg=${flag}"]) env.NIX_LDFLAGS |> lib.flatten);

    GOFLAGS = [ "-ldflags=-linkmode=external" ];
  };
in {
  buildInputs = prevAttrs.buildInputs or [ ]
    ++ optionals overrideAlloc [ pkgs.mimalloc ];

  env = prevAttrs.env or { }
    // (filterAttrs (n: v: !prevAttrs ? ${n}) env |> mapAttrs (n: v: toList prevAttrs.env.${n} or [ ] ++ v |> toString))
} // (filterAttrs (n: v: prevAttrs ? ${n}) env |> mapAttrs (n: v: toList prevAttrs.${n} ++ v))) stdenv';
