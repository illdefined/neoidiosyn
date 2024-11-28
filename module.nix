{ lib, config, pkgs, ... }: {
  environment.memoryAllocator.provider = lib.mkForce "mimalloc";

  networking = {
    nftables.enable = lib.mkDefault true;
    useNetworkd = lib.mkDefault true;
  };

  services.dbus.implementation = lib.mkDefault "broker";
}
