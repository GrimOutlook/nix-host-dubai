{ pkgs, ... }:
{
  services.cage = {
    enable = true;
    user = "kiosk";
    program = ''
      ${pkgs.epiphany}/bin/epiphany --application-mode https://localhost:8123
    '';
  };
}
