let
  # Personal key, used to encrypt/decrypt secrets when editing with `agenix -e`.
  pi = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA+VOouatDdN2oqpwfDtzJqDvrx9YJwbvs3of1aZ8Q24";

  # dubai's SSH host key, used so the running system can decrypt secrets at boot.
  dubai = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIBZlGGRPFFqLfL0Zw/Z/R3eD07rArDhF4VURRmnAC2wo";
in
{
  "mqtt-password.age".publicKeys = [
    pi
    dubai
  ];
}
