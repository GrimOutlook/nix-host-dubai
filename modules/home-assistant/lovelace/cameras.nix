{ }:
{
  title = "Cameras";
  path = "cameras";
  icon = "mdi:cctv";
  cards = [
    {
      type = "custom:advanced-camera-card";
      title = "Driveway";
      live.controls.builtin = false;
      cameras = [
        {
          camera_entity = "camera.driveway";
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Front Door";
      live.controls.builtin = false;
      cameras = [
        {
          camera_entity = "camera.front_door";
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Back Gate";
      live.controls.builtin = false;
      cameras = [
        {
          camera_entity = "camera.back_gate";
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Front Lawn";
      live.controls.builtin = false;
      cameras = [
        {
          camera_entity = "camera.front_lawn";
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    }
    {
      type = "custom:advanced-camera-card";
      title = "Library";
      live.controls.builtin = false;
      cameras = [
        {
          camera_entity = "camera.library";
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    }
  ];
}
