{ }:
rec {
  mkCameraCard =
    title: camera_entity:
    {
      type = "custom:advanced-camera-card";
      inherit title;
      live.controls.builtin = false;
      cameras = [
        {
          inherit camera_entity;
          live_provider = "go2rtc";
          go2rtc.modes = [
            "hls"
            "mse"
          ];
        }
      ];
    };
}
