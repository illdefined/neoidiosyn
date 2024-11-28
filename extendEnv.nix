{ lib, addAttrsToDerivation }: let
  inherit (lib) toList filterAttrs mapAttrs;
in env: addAttrsToDerivation (prevAttrs: {
  env = prevAttrs.env or { }
    // (filterAttrs (n: v: !prevAttrs ? ${n}) env |> mapAttrs (n: v: toList prevAttrs.env.${n} or [ ] ++ v |> toString));
} // (filterAttrs (n: v: prevAttrs ? ${n}) env |> mapAttrs (n: v: toList prevAttrs.${n} ++ v)))
