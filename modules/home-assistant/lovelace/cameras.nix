{ }:
{
  title = "Cameras";
  path = "cameras";
  icon = "mdi:cctv";
  cards = [
    {
      type = "custom:advanced-camera-card";
      title = "Driveway";
      cameras = [
        {
          camera_entity = "camera.driveway";
          live_provider = "go2rtc";
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Front Door";
      cameras = [
        {
          camera_entity = "camera.front_door";
          live_provider = "go2rtc";
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Back Gate";
      cameras = [
        {
          camera_entity = "camera.back_gate";
          live_provider = "go2rtc";
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Library";
      cameras = [
        {
          camera_entity = "camera.library";
          live_provider = "go2rtc";
        }
      ];
    }
  ];
}
