{ lib, ... }: final: prev: let
  final' = final;
  prev' = prev;

  inherit (final) stdenv;

  alias = target: pkg: final.runCommand target { } ''
    mkdir -p "$out/bin"
    ln -s "${lib.getExe pkg}" "$out/bin/${target}"
  '';

  fetchFromGitHub = let
    fetchzip = final.buildPackages.fetchzip.override { withUnzip = false; };
  in lib.makeOverridable ({ owner, repo, rev, hash, ... }: fetchzip {
    url = "https://github.com/${owner}/${repo}/archive/${rev}.tar.gz";
    inherit hash;
  });
in {
  # memory allocation
  mimalloc = (prev.mimalloc.overrideAttrs (prevAttrs: {
    cmakeFlags = let
      cppdefs = {
        MI_DEFAULT_EAGER_COMMIT = 0;
        MI_DEFAULT_ALLOW_LARGE_OS_PAGES = 1;
      } |> lib.mapAttrsToList (name: value: "${name}=${toString value}")
        |> lib.concatStringsSep ";";
    in prevAttrs.cmakeFlags or [ ] ++ [
      "-DMI_LIBC_MUSL=ON"
      ''-DMI_EXTRA_CPPDEFS="${cppdefs}"''
    ];
  })).override { secureBuild = true; };

  gperftools = null;
  jemalloc = null;
  rust-jemalloc-sys = null;

  # Package replacements
  nix = final.nix;
  jq = alias "jq" final.jaq;
  zlib = final.callPackage ./zlib.nix { };
  minizip = final.minizip-ng;

  # cURL
  curl = prev.curl.override {    
    gssSupport = false;
    http3Support = true;
    scpSupport = false;
    zstdSupport = true;

    openssl = final.quictls;
  };

  # cURL HTTP3 dependencies
  ngtcp2 = prev.ngtcp2.override { inherit fetchFromGitHub; };
  nghttp3 = prev.nghttp3.override { inherit fetchFromGitHub; };

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

      # incompatible with Clang
      libdc1394 = null;
    };
  };

  llvmPackages = prev.llvmPackages // {
    compiler-rt = prev.llvmPackages.compiler-rt.override { doFakeLibgcc = true; };
  };

  netbsd = prev.netbsd.overrideScope (final: prev: {
    compatIfNeeded = [ final.compat ];

    compat = prev.compat.overrideAttrs (prevAttrs: {
      makeFlags = prevAttrs.makeFlags ++ [ "OBJCOPY=:" ];
    });
  });

  # Perl
  perlPackages = prev.perlPackages.overrideScope (final: prev: {
    BCOW = prev.BCOW.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc ];
    });

    Clone = prev.Clone.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc ];
    });

    DBI = prev.DBI.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc ];
      makeMakerFlags = prevAttrs.makeMakerFlags or [ ] ++ [ "CCFLAGS=-Doff64_t=off_t" ];
    });

    PadWalker = prev.PadWalker.overrideAttrs (prevAttrs: {
      nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc ];
    });
  });

  # Python
  python3 = final.python313;
  python313 = prev.python313.override {
    packageOverrides = final: prev: {
      freezegun = prev.freezegun.overrideAttrs {
        doCheck = false;
        doInstallCheck = false;
      };

      mocket = prev.mocket.overrideAttrs {
        doCheck = false;
        doInstallCheck = false;
      };

      pyflakes = prev.pyflakes.overrideAttrs {
        doCheck = false;
        doInstallCheck = false;
      };

      sphinx = prev.sphinx.overrideAttrs {
        doCheck = false;
        doInstallCheck = false;
      };
    };
  };

  python3Packages = final.python313Packages;
  python313Packages = final.python313.pkgs;

  rustPackages = prev.rustPackages.overrideScope (final: prev: {
    rustc-unwrapped = prev.rustc-unwrapped.overrideAttrs (prevAttrs: {
      NIX_LDFLAGS = lib.toList prevAttrs.NIX_LDFLAGS or [ ] ++ [
        "-rpath" "${final'.llvmPackages.libunwind}/lib"
      ];
    });
  });

  # individual packages
  SDL2 = prev.SDL2.override {
    alsaSupport = false;
    x11Support = false;
  };
  
  beam = prev.beam_nox;
  cairo = prev.cairo.override { x11Support = false; };

  ceph = prev.ceph.override {
    openldap = null;
    libxfs = null;
    zfs = null;
  };

  conduwuit = prev.conduwuit.override { enableJemalloc = false; };

  cups = prev.cups.overrideAttrs {
    autoVarInit = "zero";
    boundsCheck = true;
  };

  dbus = prev.dbus.override { x11Support = false; };

  diffutils = prev.diffutils.overrideAttrs (prevAttrs: {
    configureFlags = prevAttrs.configureFlags or [ ] ++ [ "--disable-nls" ];

    postPatch = ''
      sed -E -i 's/test-(getopt-(gnu|posix)|(c|m|re)alloc-gnu)//g' gnulib-tests/Makefile.in
    '';
  });

  electron = prev.electron.override {
    electron-unwrapped = prev.electron.unwrapped.overrideAttrs (prevAttrs: {
      autoVarInit = true;
      boundsCheck = true;

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

  ffmpeg-headless = (prev.ffmpeg-headless.overrideAttrs {
    doCheck = false;
  }).override {
    withAlsa = false;
    withSsh = false;
  };

  ffmpeg = (prev.ffmpeg.overrideAttrs {
    doCheck = false;
  }).override {
    withAlsa = false;
    withCodec2 = true;
    withSdl2 = false;
    withSsh = false;
  };

  gd = prev.gd.override { withXorg = false; };

  gfortran = final.wrapCC (prev.gfortran.cc.override {
    stdenv = final.gccStdenv;
  });

  ghostscript = (prev.ghostscript.overrideAttrs {
    doInstallCheck = false;
  }).override { x11Support = false; };

  gnutls = prev.gnutls.overrideAttrs (prevAttrs: {
    postPatch = prevAttrs.postPatch or "" + ''
      substituteInPlace tests/Makefile.am \
        --replace-fail naked-alerts ""
    '';
  });

  gobject-introspection = prev.gobject-introspection.override { x11Support = false; };
  graphviz = prev.graphviz-nox;

  gtk3 = prev.gtk3.override {
    x11Support = false;
    xineramaSupport = false;
  };

  gtk4 = prev.gtk4.override {
    x11Support = false;
    xineramaSupport = false;
  };

  hotdoc = prev.hotdoc.overrideAttrs {
    doCheck = false;
    doInstallCheck = false;
  };

  imagemagick = prev.imagemagick.override {
    libX11Support = false;
    libXtSupport = false;
  };

  imlib2 = prev.imlib2.override { x11Support = false; };

  iproute2 = prev.iproute2.overrideAttrs (prevAttrs: {
    patches = prevAttrs.patches or [ ] ++ [
      (final.fetchpatch {
        url = "https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/patch/?id=043ef90e2fa94397eb5c85330889ca4146a6d58a";
        hash = "sha256-6q4NcdT2YXhhbMgLaiAjO2WFUcM9Pv8+J34rGzJqU5Q=";
      })
    ];
  });

  jaq = prev.jaq.overrideAttrs (prevAttrs: {
    nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc stdenv.cc.bintools ];
  });

  jdk8 = prev.jdk8_headless;
  jre8 = prev.jre8_headless;

  kexec-tools = prev.kexec-tools.overrideAttrs (prevAttrs: {
    makeFlags = prevAttrs.makeFlags or [ ] ++ [ "BUILD_KEXEC_TEST=no" ];
  });

  libdrm = prev.libdrm.override { withValgrind = false; };

  libepoxy = prev.libepoxy.overrideAttrs (prevAttrs: {
    buildInputs = prevAttrs.buildInputs or [ ] ++ [ final.libGL ];
    mesonFlags = prevAttrs.mesonFlags or [ ] ++ [ "-Degl=yes" ];
  });

  libjpeg = prev.libjpeg.overrideAttrs (prevAttrs: {
    cmakeFlags = prevAttrs.cmakeFlags or [ ] ++ [ "-DFLOATTEST12=fp-contract" ];
  });

  libpng = prev.libpng.overrideAttrs (prevAttrs: {
    postPatch = prevAttrs.postPatch or "" + ''

      substituteInPlace tests/pngtest-all \
        --replace-warn --strict --relaxed
    '';
  });

  libpng-apng = final.libpng.override { apngSupport = true; };

  librist = prev.librist.overrideAttrs (finalAttrs: prevAttrs: {
    version = assert prevAttrs.version == "0.2.10"; "0.2.11";

    src = prevAttrs.src.override {
      rev = "refs/tags/v${finalAttrs.version}";
      hash = "sha256-xWqyQl3peB/ENReMcDHzIdKXXCYOJYbhhG8tcSh36dY=";
    };

    patches = [ ];
  });

  lix = prev.lix.override { enableGC = true; };

  makeBinaryWrapper = prev.makeBinaryWrapper.overrideAttrs (prevAttrs: {
    nativeBuildInputs = prevAttrs.nativeBuildInputs or [ ] ++ [ stdenv.cc stdenv.cc.bintools ];
  });

  makeInitrdNG = prev.makeInitrdNG.overrideAttrs (prevAttrs: {
    NIX_RUSTFLAGS = prevAttrs.NIX_RUSTFLAGS
    |> map (flag: if flag == "lto" then "embed-bitcode=no" else flag);
  });

  mercurial = prev.mercurial.override { re2Support = false; };

  mesa = (prev.mesa.overrideAttrs (prevAttrs: {
    outputs = prevAttrs.outputs |> lib.remove "spirv2dxil";
  })).override {
    withValgrind = false;

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
  };

  meson = prev.meson.overrideAttrs (prevAttrs: {
    preCheck = prevAttrs.preCheck or "" + ''
      rm -r -v 'test cases/common/44 pkgconfig-gen'
    '';
  });

  mpv = final.mpv-unwrapped.wrapper { mpv = final.mpv-unwrapped; };
  mpv-unwrapped = prev.mpv-unwrapped.override {
    alsaSupport = false;
    cacaSupport = false;
    openalSupport = false;
    sdl2Support = false;
    vdpauSupport = false;
    x11Support = false;
  };

  nlohmann_json = prev.nlohmann_json.override { stdenv = final.gccStdenv; };
  nodejs = prev.nodejs.overrideAttrs { doCheck = false; };
  nodejs-slim = prev.nodejs-slim.overrideAttrs { doCheck = false; };
  openjdk8 = prev.openjdk_headless;

  openssh = prev.openssh.overrideAttrs {
    autoVarInit = "zero";
    boundsCheck = true;
  };
  
  pango = prev.pango.override { x11Support = false; };
  pipewire = prev.pipewire.override { x11Support = false; };

  sioyek = prev.sioyek.overrideAttrs {
    autoVarInit = "zero";
    boundsCheck = true;
  };

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
        "-DSQLITE_DEFAULT_MEMSTATUS=0"        

        # I/O
        "-DSQLITE_DEFAULT_MMAP_SIZE=281474976710656"
        "-DSQLITE_MAX_MMAP_SIZE=281474976710656"
        "-DSQLITE_DEFAULT_FILE_PERMISSIONS=0600"
        "-DSQLITE_DEFAULT_WAL_SYNCHRONOUS=1"
        "-DSQLITE_DEFAULT_WORKER_THREADS=4"
        "-USQLITE_SECURE_DELETE"
        "-DSQLITE_ENABLE_NULL_TRIM"

        # omit certain interfaces
        "-DSQLITE_DQS=0"
        "-DSQLITE_LIKE_DOESNT_MATCH_BLOBS"        
        #"-DSQLITE_OMIT_DEPRECATED"
        "-DSQLITE_OMIT_LOOKASIDE"
        #"-DSQLITE_OMIT_PROGRESS_CALLBACK"
        "-DSQLITE_OMIT_SHARED_CACHE"
        #"-DSQLITE_OMIT_UTF16"
      ] |> toString;
    };
  });

  systemd = (prev.systemd.overrideAttrs {
    boundsCheck = true;
  }).override {
    withApparmor = false;
    withIptables = false;
  };

  usrsctp = prev.usrsctp.overrideAttrs (prevAttrs: {
    cmakeFlags = prevAttrs.cmakeFlags or [ ] ++ [ "-Dsctp_werror=0" ];
  });

  vim-full = prev.vim-full.override { guiSupport = false; };
  wayland = prev.wayland.override { withDocumentation = false; };

  w3m = prev.w3m.override {
    x11Support = false;
    imlib2 = final.imlib2;
  };

  wasilibc = prev.wasilibc.overrideAttrs (finalAttrs: prevAttrs: {
    version = "24";

    src = prevAttrs.src.override {
      rev = "refs/tags/wasi-sdk-${finalAttrs.version}";
      hash = "sha256-wfOvOWVJDH5+tC5pSTLV5FUPqf25W+A2N/vXlq4nSmk=";
    };
  });

  xvfb-run = final.callPackage ./xvfb-run.nix {
    cage = final.cage.override {
      wlroots = final.wlroots.override { enableXWayland = false; };
      xwayland = null;
    };
  };
} // lib.optionalAttrs (!prev.stdenv.buildPlatform.isx86) {
  writeShellApplication = { ... }@args: prev.writeShellApplication (args // {
    checkPhase = args.checkPhase or ''
      runHook preCheck
      ${stdenv.shellDryRun} "$target"
      runHook postCheck
    '';
  });

  # JDK 17 is not available for RISC-V and ARM
  jdk17 = final.jdk21_headless;
  jdk17_headless = final.jdk21_headless;

  sudo-rs = (prev.sudo-rs.overrideAttrs {
    postInstall = "";
  }).override {
    pandoc = null;
  };
}
