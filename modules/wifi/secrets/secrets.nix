let
  dubai = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZlGGRPFFqLfL0Zw/Z/R3eD07rArDhF4VURRmnAC2wo";
in
{
  "wifi.age".publicKeys = [ dubai ];
}
