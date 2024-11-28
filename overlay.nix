final: prev: let
  inherit (prev) lib stdenv;
  inherit (stdenv) buildPlatform hostPlatform;
  inherit (lib) toList optionals;

  fetchFromGitHub = let
    fetchzip = final.buildPackages.fetchzip.override { withUnzip = false; };
  in lib.makeOverridable ({ owner, repo, rev, hash, ... }: fetchzip {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    inherit hash;
  });
in {
  # stdenv
  extendEnv = final.callPackage ./extendEnv.nix { };

  clangStdenv = let
    inherit (final) overrideCC llvmPackages;
    stdenv = overrideCC prev.stdenv (llvmPackages.clangUseLLVM.override {
      inherit (llvmPackages) bintools;
    });
  in final.extendEnv {
    NIX_CFLAGS_COMPILE_BEFORE = [ "-flto" "-ffp-contract=fast-honor-pragmas" ];
    NIX_LDFLAGS_BEFORE = [ "--icf=safe" "--lto-O2" ];
    NIX_RUSTFLAGS = [
      "-C" "linker-plugin-lto"
      "-C" "linker=${lib.getExe stdenv.cc}"
    ];
  } stdenv;

  hardenedStdenv = final.extendEnv {
    NIX_CFLAGS_COMPILE_BEFORE = [
      "-ftrivial-auto-var-init=zero"
      "-fsanitize-minimal-runtime"
      "-fsanitize=bounds,object-size,vla-bound"
    ];

    NIX_LDFLAGS = [ "${lib.getLib final.mimalloc}/lib/mimalloc-secure.o" ];
  } final.clangStdenv;

  # memory allocation
  mimalloc = (prev.mimalloc.overrideAttrs (prevAttrs: {
    cmakeFlags = let
      cppdefs = {
        MI_DEFAULT_EAGER_COMMIT = 0;
        MI_DEFAULT_ALLOW_LARGE_OS_PAGES = 1;
      } |> lib.mapAttrsToList (name: value: "${name}=${toString value}")
        |> lib.concatStringsSep ";";
    in prevAttrs.cmakeFlags or [ ] ++ [ ''-DMI_EXTRA_CPPDEFS="${cppdefs}"'' ];
  })).override {
    secureBuild = true;

    stdenv = final.clangStdenv;
  };

  # incompatible allocators
  gperftools = null;
  jemalloc = null;
  rust-jemalloc-sys = null;

  # package alternatives
  nix = final.lix;
  zlib = final.callPackage ./zlib.nix { };
  minizip = final.minizip-ng;

  blas = prev.blas.override { blasProvider = final.blis; };
  blis = (prev.blis.overrideAttrs (prevAttrs: {
    buildInputs = prevAttrs.buildInputs or [ ] ++ [ final.llvmPackages.openmp ];

    env = prevAttrs.env or { } // {
      NIX_CFLAGS_COMPILE = toList prevAttrs.env.NIX_CFLAGS_COMPILE or [ ]
        ++ optionals hostPlatform.isx86 [ "-fno-lto" ] |> toString;
    };

    meta = prevAttrs.meta or { } // { platforms = lib.platforms.all; };
  })).override {
    withArchitecture =
      if hostPlatform.isRiscV then "rv64i"
      else if hostPlatform.isAarch then "arm64"
      else if hostPlatform.isx86 then "x86_64"
      else "generic";

    stdenv = final.clangStdenv;
  };

  # cURL
  curl = prev.curl.override {    
    gssSupport = false;
    #http3Support = true;
    scpSupport = false;
    zstdSupport = true;

    stdenv = final.clangStdenv;
  };

  # cURL HTTP3 dependencies
  #ngtcp2 = prev.ngtcp2.override { inherit fetchFromGitHub; };
  #nghttp3 = prev.nghttp3.override { inherit fetchFromGitHub; };

  # scopes
  gst_all_1 = prev.gst_all_1 // {
    gst-plugins-base = prev.gst_all_1.gst-plugins-base.override {
      enableAlsa = false;
      enableX11 = false;
    };
 
    gst-plugins-good = prev.gst_all_1.gst-plugins-good.override {
      enableJack = false;
      enableX11 = false;
 
      aalib = null;
      libcaca = null;
    }; 
    gst-plugins-bad = prev.gst_all_1.gst-plugins-bad.override {
      guiSupport = false;
    };
  };

  rustPlatform = prev.rustPlatform // {
    buildRustPackage = prev.rustPlatform.buildRustPackage.override {
      stdenv = final.clangStdenv;
    };
  };

  # individual packages
  SDL2 = prev.SDL2.override {
    alsaSupport = false;
    x11Support = false;
  };

  beam = prev.beam_nox;
  cairo = prev.cairo.override { x11Support = false; };

  conduwuit = prev.conduwuit.override { enableJemalloc = false; };
  dbus = prev.dbus.override { x11Support = false; };
  dconf = prev.dconf.overrideAttrs { doCheck = false; };

  electron = prev.electron.override {
    stdenv = final.hardenedStdenv;

    electron-unwrapped = prev.electron.unwrapped.overrideAttrs (prevAttrs: {
      gnFlags = prevAttrs.gnFlags or "" + ''
        # Disable X11
        ozone_platform_x11 = false

        # Disable internal memory allocator
        use_partition_alloc_as_malloc = false
        enable_backup_ref_ptr_support = false
        enable_pointer_compression_support = false
      '';
    });
  };

  ffmpeg-headless = prev.ffmpeg-headless.override {
    withAlsa = false;
    withSsh = false;
  };

  ffmpeg = prev.ffmpeg.override {
    withAlsa = false;
    withCodec2 = true;
    withSdl2 = false;
    withSsh = false;
  };

  gd = prev.gd.override { withXorg = false; };

  ghostscript = prev.ghostscript.override {
    x11Support = false;
    stdenv = final.hardenedStdenv;
  };

  gobject-introspection = prev.gobject-introspection.override { x11Support = false; };
  graphviz = prev.graphviz-nox;

  gtk3 = prev.gtk3.override {
    x11Support = false;
    xineramaSupport = false;

    stdenv = final.clangStdenv;
  };

  gtk4 = prev.gtk4.override {
    x11Support = false;
    xineramaSupport = false;

    stdenv = final.clangStdenv;
  };

  imlib2 = prev.imlib2.override { x11Support = false; };

  jdk8 = prev.jdk8_headless;
  jre8 = prev.jre8_headless;

  libjpeg = final.libjpeg_turbo;
  libjpeg_turbo = (prev.libjpeg_turbo.overrideAttrs (prevAttrs: {
    postPatch = prevAttrs.postPatch or "" + ''
      cat >>CMakeLists.txt <<EOF
      set_tests_properties(djpeg12-shared-3x2-float-prog-cmp PROPERTIES DISABLED True)
      EOF
    '';

    cmakeFlags = prevAttrs.cmakeFlags or [ ] ++ [ "-DFLOATTEST12=fp-contract" ];    
  })).override { stdenv = final.clangStdenv; };

  libpng = (prev.libpng.overrideAttrs (prevAttrs: {
    postPatch = prevAttrs.postPatch or "" + ''

      substituteInPlace tests/pngtest-all \
        --replace-warn --strict --relaxed
    '';
  })).override { stdenv = final.clangStdenv; };

  libpng-apng = final.libpng.override { apngSupport = true; };

  lix = prev.lix.override { enableGC = true; };

  lkl = prev.lkl.overrideAttrs (prevAttrs: {
    env = prevAttrs.env or { } // {
      NIX_CFLAGS_COMPILE = toList prevAttrs.env.NIX_CFLAGGS_COMPILE or [ ] ++ [ "--hash-style=both" ] |> toString;
    };
  });

  mesa = (prev.mesa.overrideAttrs (prevAttrs: {
    outputs = prevAttrs.outputs |> lib.remove "spirv2dxil";
  })).override {
    galliumDrivers = [
      "llvmpipe"
      "nouveau"
      "radeonsi"
      "virgl"
      "zink"
    ];

    vulkanDrivers = [
      "amd"
      "intel"
      "nouveau"
      "swrast"
      "virtio"
    ];

    stdenv = final.clangStdenv;
  };

  mpv = final.mpv-unwrapped.wrapper { mpv = final.mpv-unwrapped; };
  mpv-unwrapped = prev.mpv-unwrapped.override {
    alsaSupport = false;
    cacaSupport = false;
    openalSupport = false;
    sdl2Support = false;
    vdpauSupport = false;
    x11Support = false;

    stdenv = final.clangStdenv;
  };

  nodejs = prev.nodejs.overrideAttrs { doCheck = false; };
  nodejs-slim = prev.nodejs-slim.overrideAttrs { doCheck = false; };
  pango = prev.pango.override { x11Support = false; };

  patchelf = prev.patchelf.overrideAttrs (prevAttrs: {
    patches = prevAttrs.patches or [ ] ++ [ ./patches/patchelf-hash-optional.patch ];
  });
  
  pipewire = prev.pipewire.override {
    x11Support = false;
    stdenv = final.clangStdenv;
  };

  postgresql = prev.postgresql.override { gssSupport = false; };

  rocksdb = prev.rocksdb.overrideAttrs (prevAttrs: {
    env = prevAttrs.env or { } // {
      NIX_CFLAGS_COMPILE = toList prevAttrs.env.NIX_CFLAGS_COMPILE or [ ]
        ++ optionals hostPlatform.sse4_2Support [ "-msse2" "-mpclmul" ] |> toString;
    };
  });

  sqlite = prev.sqlite.overrideAttrs (prevAttrs: {
    env = prevAttrs.env or { } // {
      NIX_CFLAGS_COMPILE = lib.toList prevAttrs.env.NIX_CFLAGS_COMPILE or [ ] ++ [
        "-DSQLITE_THREADSAFE=2"

        # memory allocation
        "-DSQLITE_DEFAULT_PAGE_SIZE=2097152"
        "-DSQLITE_DEFAULT_CACHE_SIZE=-64"
        "-DSQLITE_DEFAULT_PCACHE_INITSZ=1"
        "-DSQLITE_MALLOC_SOFT_LIMIT=0"
        "-DSQLITE_USE_ALLOCA"
        #"-DSQLITE_DEFAULT_MEMSTATUS=0"

        "-DSQLITE_OMIT_LOOKASIDE"
        #"-DSQLITE_OMIT_SHARED_CACHE"

        # I/O
        "-DSQLITE_DEFAULT_MMAP_SIZE=281474976710656"
        "-DSQLITE_MAX_MMAP_SIZE=281474976710656"
        "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600"
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1"
        "-DSQLITE_DEFAULT_WORKER_THREADS=4"
        "-USQLITE_SECURE_DELETE"
        "-DSQLITE_ENABLE_NULL_TRIM"
      ] |> toString;
    };
  });

  systemd = prev.systemd.override {
    withApparmor = false;
    withIptables = false;
  };

  umockdev = prev.umockdev.overrideAttrs { doCheck = false; };
  uutils-coreutils = prev.uutils-coreutils.override { stdenv = final.clangStdenv; };

  vim-full = prev.vim-full.override { guiSupport = false; };

  w3m = prev.w3m.override {
    x11Support = false;
    imlib2 = final.imlib2;
  };

  wayland = prev.wayland.override {
    withDocumentation = false;
    stdenv = final.clangStdenv;
  };

  wireplumber = prev.wireplumber.override {
    stdenv = final.clangStdenv;
  };

  xvfb-run = final.callPackage ./xvfb-run.nix {
    cage = final.cage.override {
      wlroots = final.wlroots.override { enableXWayland = false; };
      xwayland = null;
    };
  };
} // lib.optionalAttrs (!buildPlatform.isx86) {
  # no shellcheck on RISC-V and ARM
  writeShellApplication = { ... }@args: prev.writeShellApplication (args // {
    checkPhase = args.checkPhase or ''
      runHook preCheck
      ${stdenv.shellDryRun} "$target"
      runHook postCheck
    '';
  });

  # Tests fail in QEMU
  libuv = prev.libuv.overrideAttrs { doCheck = false; };

  # no GHC support for RISC-V and ARM
  pandoc = null;

  # no pandoc on RISC-V and ARM
  sudo-rs = prev.sudo-rs.overrideAttrs {
    postInstall = "";
  };
} // lib.optionalAttrs (!hostPlatform.isx86) {
  # JDK 17 is not available for RISC-V and ARM
  jdk17 = final.jdk21_headless;
  jdk17_headless = final.jdk21_headless;
}
