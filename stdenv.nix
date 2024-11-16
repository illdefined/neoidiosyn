{ lib, pkgs, ... }: { ... }@attrs: let
  stdenv' = attrs.stdenv or attrs.baseStdenv;
  pkgs' = attrs.pkgs or attrs.buildPackages;

  inherit (pkgs') stdenv;
  inherit (stdenv) buildPlatform hostPlatform targetPlatform;
  inherit (stdenv.cc) isClang nativePrefix targetPrefix;
  inherit (stdenv.cc.bintools) isLLVM;

  inherit (lib) optionals optionalAttrs toList;
in pkgs.addAttrsToDerivation (prevAttrs: let
  autoVarInit = prevAttrs.autoVarInit or null;
  boundsCheck = prevAttrs.boundsCheck or false;
  overrideAlloc = prevAttrs.overrideAlloc or true;  

  cflags = [ "-pipe" "-fno-semantic-interposition" ]
    ++ optionals isClang [ "-ffp-contract=fast-honor-pragmas" ]
    ++ optionals isLLVM [ "-flto" ]
    ++ optionals (autoVarInit != null) [ "-ftrivial-auto-var-init=${autoVarInit}" ]
    ++ optionals boundsCheck [ "-fsanitize-trap=bounds,object-size,vla-bound" ];

  cflagsl = isClang [ "--ld-path=${lib.getExe' stdenv.cc.bintools (targetPrefix + "ld")}" ];

  ldflags = [ "-O2" "--hash-style=gnu" ]
    ++ optionals isLLVM [ "--icf=safe" "--lto-O2" ]
    ++ optionals overrideAlloc [ "-lmimalloc" ];

  rustflags = [
    "-C" "opt-level=2"
    "-C" "linker-flavor=ld.lld"
    "-C" "lto"
    "-C" "linker-plugin-lto"
    "-C" "target-cpu=${targetPlatform.gcc.arch}"
    "-C" "link-arg=-O2"
    "-C" "link-arg=--hash-style=gnu"
    "-C" "link-arg=--icf=safe"
    "-C" "link-arg=--lto-O2"
  ] ++ optionals overrideAlloc [ "-C" "link-arg=-lmimalloc" ];

  goflags = [ "-ldflags=-linkmode=external" ];
in {
  buildInputs = prevAttrs.buildInputs or [ ]
    ++ optionals overrideAlloc [ pkgs.mimalloc ];

  env = prevAttrs.env or { }
  // optionalAttrs (prevAttrs ? env.NIX_CFLAGS_COMPILE)
    { NIX_CFLAGS_COMPILE = toList prevAttrs.env.NIX_CFLAGS_COMPILE or [ ] ++ cflags |> toString; }
  // optionalAttrs (prevAttrs ? env.NIX_CFLAGS_LINK)
    { NIX_CFLAGS_LINK = toList prevAttrs.env.NIX_CFLAGS_LINK or [ ] ++ cflagsl |> toString; }
  // optionalAttrs (prevAttrs ? env.NIX_LDFLAGS)
    { NIX_LDFLAGS = toList prevAttrs.env.NIX_LDFLAGS or [ ] ++ ldflags |> toString; };

  NIX_RUSTFLAGS = toList prevAttrs.NIX_RUSTFLAGS or [ ] ++ rustflags;
  GOFLAGS = toList prevAttrs.NIX_GOFLAGS or [ ] ++ goflags;
}
// optionalAttrs (!prevAttrs ? env.NIX_CFLAGS_COMPILE)
  { NIX_CFLAGS_COMPILE = toList prevAttrs.NIX_CFLAGS_COMPILE or [ ] ++ cflags; }
// optionalAttrs (!prevAttrs ? env.NIX_CFLAGS_LINK)
  { NIX_CFLAGS_LINK = toList prevAttrs.NIX_CFLAGS_LINK or [ ] ++ cflagsl; }
// optionalAttrs (!prevAttrs ? env.NIX_LDFLAGS)
  { NIX_LDFLAGS = toList prevAttrs.NIX_LDFLAGS or [ ] ++ ldflags; }
) stdenv';
