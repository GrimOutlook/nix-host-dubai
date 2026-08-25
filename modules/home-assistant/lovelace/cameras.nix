{ mkCameraCard ? (import ./helpers.nix { }).mkCameraCard }:
{
  title = "Cameras";
  path = "cameras";
  icon = "mdi:cctv";
  cards = [
    (mkCameraCard "Driveway" "camera.driveway")
    (mkCameraCard "Front Door" "camera.front_door")
    (mkCameraCard "Back Gate" "camera.back_gate")
    (mkCameraCard "Front Lawn" "camera.front_lawn")
    (mkCameraCard "Library" "camera.library")
  ];
}
