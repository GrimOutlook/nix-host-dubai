{ mkCameraCard ? (import ./helpers.nix { }).mkCameraCard }:
{
  title = "Pets";
  path = "pets";
  icon = "mdi:paw";
  cards = [
    (mkCameraCard "Library" "camera.library")
    {
      type = "entities";
      title = "Jem";
      icon = "mdi:cat";
      entities = [
        {
          entity = "sensor.feed_jem_last_fed";
          name = "Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_jem_last_activity";
          name = "Last Activity";
          icon = "mdi:rfid";
        }
      ];
    }
    {
      type = "entities";
      title = "Willow";
      icon = "mdi:cat";
      entities = [
        {
          entity = "sensor.feed_willow_last_fed";
          name = "Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_willow_last_activity";
          name = "Last Activity";
          icon = "mdi:rfid";
        }
      ];
    }
    {
      type = "entities";
      title = "Fern";
      icon = "mdi:cat";
      entities = [
        {
          entity = "sensor.feed_fern_last_fed";
          name = "Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_fern_last_activity";
          name = "Last Activity";
          icon = "mdi:rfid";
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
              entity = "input_boolean.feed_jem_low_food";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_jem_low_food";
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
              entity = "input_boolean.feed_willow_low_food";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_willow_low_food";
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
              entity = "input_boolean.feed_fern_low_food";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_fern_low_food";
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
              entity = "input_boolean.feed_jem_jam";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_jem_jam";
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
              entity = "input_boolean.feed_willow_jam";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_willow_jam";
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
              entity = "input_boolean.feed_fern_jam";
              state = "on";
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
                  service = "input_boolean.turn_off";
                  target = {
                    entity_id = "input_boolean.feed_fern_jam";
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
