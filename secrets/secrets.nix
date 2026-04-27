let
  paris = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHw6y8P3yv2xkLTl93JhF4DiCHjWrk0RzlY1Iwdz7tJL grim@paris";
in
{
  "wifi.age" = {
    publicKeys = [ paris ];
    armor = true;
  };
}
