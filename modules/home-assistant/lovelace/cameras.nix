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
      dimensions = {
        aspect_ratio_mode = "static";
        aspect_ratio = "16:9";
      };
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
      dimensions = {
        aspect_ratio_mode = "static";
        aspect_ratio = "16:9";
      };
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
      dimensions = {
        aspect_ratio_mode = "static";
        aspect_ratio = "16:9";
      };
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
