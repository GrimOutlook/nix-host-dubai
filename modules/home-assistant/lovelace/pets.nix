{ }:
{
  title = "Pets";
  path = "pets";
  icon = "mdi:paw";
  cards = [
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
    {
      type = "entities";
      title = "Pet Feeders";
      entities = [
        {
          entity = "sensor.feed_jem_last_fed";
          name = "Jem Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_willow_last_fed";
          name = "Willow Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_fern_last_fed";
          name = "Fern Last Fed";
          icon = "mdi:food-drumstick";
        }
      ];
    }
    {
      type = "vertical-stack";
      cards = [
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_jem_low_food";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "⚠️ **Low Food Warning:** Feeder **feed-jem** reported LOW_FOOD. Please refill the food hopper.";
              }
              {
                type = "button";
                name = "Dismiss Jem Low Food Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_jem_low_food";
                  };
                };
              }
            ];
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_willow_low_food";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "⚠️ **Low Food Warning:** Feeder **feed-willow** reported LOW_FOOD. Please refill the food hopper.";
              }
              {
                type = "button";
                name = "Dismiss Willow Low Food Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_willow_low_food";
                  };
                };
              }
            ];
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_fern_low_food";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "⚠️ **Low Food Warning:** Feeder **feed-fern** reported LOW_FOOD. Please refill the food hopper.";
              }
              {
                type = "button";
                name = "Dismiss Fern Low Food Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_fern_low_food";
                  };
                };
              }
            ];
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_jem_jam";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "🚨 **Feed Jam Alert:** Feeder **feed-jem** reported a grain jam! Please inspect and clear the dispenser.";
              }
              {
                type = "button";
                name = "Dismiss Jem Jam Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_jem_jam";
                  };
                };
              }
            ];
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_willow_jam";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "🚨 **Feed Jam Alert:** Feeder **feed-willow** reported a grain jam! Please inspect and clear the dispenser.";
              }
              {
                type = "button";
                name = "Dismiss Willow Jam Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_willow_jam";
                  };
                };
              }
            ];
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "persistent_notification.feed_fern_jam";
              state_not = "unavailable";
            }
          ];
          card = {
            type = "vertical-stack";
            cards = [
              {
                type = "markdown";
                content = "🚨 **Feed Jam Alert:** Feeder **feed-fern** reported a grain jam! Please inspect and clear the dispenser.";
              }
              {
                type = "button";
                name = "Dismiss Fern Jam Alert";
                icon = "mdi:bell-off";
                tap_action = {
                  action = "call-service";
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "feed_fern_jam";
                  };
                };
              }
            ];
          };
        }
      ];
    }
  ];
}
