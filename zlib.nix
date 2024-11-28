{ lib, stdenv, fetchurl, zlib-ng, ... }:

assert zlib-ng.version == "2.2.2";

stdenv.mkDerivation (finalAttrs: {
  inherit (zlib-ng) pname version meta;

  src = fetchurl {
    url = "https://github.com/zlib-ng/zlib-ng/archive/refs/tags/${finalAttrs.version}.tar.gz";
    hash = "sha256-/LQd1Zo/FwAq6xuyHwRpbJtyFASJC7lFxas50stpZUw=";
  };

  outputs = [ "out" "dev" "man" ];

  setOutputFlags = false;
  dontAddDisableDepTrack = true;
  configurePlatforms = [ ];

  env = {
    CHOST = stdenv.hostPlatform.config;
  };

  configureFlags = [
    "--libdir=${placeholder "dev"}/lib"
    "--sharedlibdir=${placeholder "out"}/lib"
    "--includedir=${placeholder "dev"}/include"
    "--zlib-compat"
  ];

  makeFlags = [ "mandir=$(man)/share/man" ];
})
