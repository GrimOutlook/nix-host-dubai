{
  homelab,
  host,
  host-info,
  ...
}:
{
  _module.args = {
    inherit homelab;
    inherit host-info;
    inherit host;
  };

  imports = [
    ./homeassistant.nix
  ];
}
