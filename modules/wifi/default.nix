{
  config,
  ...
}:
{
  age.secrets.wifi = {
    file = ./secrets/wifi.age;
    owner = "root";
    mode = "0400";
  };
  networking.networkmanager = {
    enable = true;
    ensureProfiles = {
      environmentFiles = [ config.age.secrets.wifi.path ];
      profiles = {
        # Deliberately not pinned to an `interface-name`: the wifi NIC was
        # renamed `wlan0` -> `wld0` by a kernel bump, which stranded the
        # hand-made profile and left the box with no address at boot.
        my-wifi = {
          connection = {
            id = "MLH";
            type = "wifi";
          };
          wifi = {
            mode = "infrastructure";
            ssid = "MLH";
          };
          wifi-security = {
            auth-alg = "open";
            key-mgmt = "wpa-psk";
            psk = "$NM_WIFI_PSK";
          };
          ipv4.method = "auto";
          ipv6.method = "auto";
        };
      };
    };
  };
}
