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

  rustflags = [ "-C" "opt-level=2" "-C" "target-cpu=${targetPlatform.gcc.arch}" ]
    ++ optionals isLLVM [ "-C" "lto" "-C" "linker-plugin-lto" ]
    ++ (map (flag: [ "-C" "link-arg=${flag}"]) ldflags |> lib.flatten);

  goflags = [ "-ldflags=-linkmode=external" ];
in {
  buildInputs = prevAttrs.buildInputs or [ ]
    ++ optionals overrideAlloc [ pkgs.mimalloc ];

  env = prevAttrs.env or { }
  // optionalAttrs (!prevAttrs ? NIX_CFLAGS_COMPILE)
    { NIX_CFLAGS_COMPILE = toList prevAttrs.env.NIX_CFLAGS_COMPILE or [ ] ++ cflags |> toString; }
  // optionalAttrs (!prevAttrs ? NIX_CFLAGS_LINK)
    { NIX_CFLAGS_LINK = toList prevAttrs.env.NIX_CFLAGS_LINK or [ ] ++ cflagsl |> toString; }
  // optionalAttrs (!prevAttrs ? NIX_LDFLAGS)
    { NIX_LDFLAGS = toList prevAttrs.env.NIX_LDFLAGS or [ ] ++ ldflags |> toString; }
  // optionalAttrs (!prevAttrs ? NIX_RUSTFLAGS)
    { NIX_RUSTFLAGS = toList prevAttrs.NIX_RUSTFLAGS or [ ] ++ rustflags |> toString; }
  // optionalAttrs (!prevAttrs ? GOFLAGS)
    { GOFLAGS = toList prevAttrs.GOFLAGS or [ ] ++ goflags |> toString; };
}
// optionalAttrs (prevAttrs ? NIX_CFLAGS_COMPILE)
  { NIX_CFLAGS_COMPILE = toList prevAttrs.NIX_CFLAGS_COMPILE or [ ] ++ cflags; }
// optionalAttrs (prevAttrs ? NIX_CFLAGS_LINK)
  { NIX_CFLAGS_LINK = toList prevAttrs.NIX_CFLAGS_LINK or [ ] ++ cflagsl; }
// optionalAttrs (prevAttrs ? NIX_LDFLAGS)
  { NIX_LDFLAGS = toList prevAttrs.NIX_LDFLAGS or [ ] ++ ldflags; }
// optionalAttrs (prevAttrs ? NIX_RUSTFLAGS)
  { NIX_RUSTFLAGS = toList prevAttrs.NIX_RUSTFLAGS or [ ] ++ rustflags; }
// optionalAttrs (prevAttrs ? GOFLAGS)
  { GOFLAGS = toList prevAttrs.GOFLAGS or [ ] ++ goflags; };
) stdenv';
