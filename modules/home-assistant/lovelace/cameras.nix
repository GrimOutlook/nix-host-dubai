{ }:
{
  title = "Cameras";
  path = "cameras";
  icon = "mdi:cctv";
  cards = [
    {
      type = "picture-entity";
      title = "Driveway";
      entity = "camera.driveway";
      camera_view = "live";
    }
    {
      type = "picture-entity";
      title = "Front Door";
      entity = "camera.front_door";
      camera_view = "live";
    }
    {
      type = "picture-entity";
      title = "Back Gate";
      entity = "camera.back_gate";
      camera_view = "live";
    }
    {
      type = "picture-entity";
      title = "Library";
      entity = "camera.library";
      camera_view = "live";
    }
  ];
}
