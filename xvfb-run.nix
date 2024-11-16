{ lib, writeShellApplication, cage }:

writeShellApplication {
  name = "xvfb-run";
  text = ''
    # Discard all options
    while [[ "$1" =~ ^- ]]; do
      case "$1" in
        (-e|-f|-n|-p|-s|-w) shift ;&
        (*) shift ;;
      esac
    done

    WLR_BACKENDS=headless \
    WLR_LIBINPUT_NO_DEVICES=1 \
    WLR_RENDERER=pixman \
    XDG_RUNTIME_DIR="$(mktemp -d)" \
      exec '${lib.getExe cage}' -- "$@"
  '';
}
