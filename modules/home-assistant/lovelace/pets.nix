{
  lib,
  mkCameraCard ? (import ./helpers.nix { }).mkCameraCard,
}:
let
  # Matches the feeder naming in feeders.nix: "feed-jem" -> key "jem",
  # label "Jem". Kept here rather than shared with feeders.nix since this
  # file only ever needs the pet's short name, not the full feeder identity.
  pets = [
    {
      name = "Jem";
      icon = "mdi:dog";
    }
    {
      name = "Willow";
      icon = "mdi:cat";
    }
    {
      name = "Fern";
      icon = "mdi:cat";
    }
  ];
  petKey = lib.toLower;
  mkPetCard =
    { name, icon }:
    let
      key = petKey name;
    in
    {
      type = "entities";
      title = name;
      inherit icon;
      entities = [
        {
          type = "conditional";
          conditions = [
            {
              entity = "binary_sensor.feed_${key}_feed_jam";
              state = "off";
            }
          ];
          row = {
            type = "text";
            name = "Status";
            icon = "mdi:check-circle";
            state = "✅ Working";
          };
        }
        {
          type = "conditional";
          conditions = [
            {
              entity = "binary_sensor.feed_${key}_feed_jam";
              state = "on";
            }
          ];
          row = {
            type = "text";
            name = "Status";
            icon = "mdi:close-circle";
            state = "❌ Jammed";
          };
        }
        {
          entity = "sensor.feed_${key}_last_fed";
          name = "Last Fed";
          icon = "mdi:food-drumstick";
        }
        {
          entity = "sensor.feed_${key}_last_activity";
          name = "Last Activity";
          icon = "mdi:rfid";
        }
      ];
    };
  mkAlertCard =
    {
      name,
      helperSuffix,
      emoji,
      label,
      shortLabel,
      message,
    }:
    let
      key = petKey name;
      helper = "input_boolean.feed_${key}_${helperSuffix}";
    in
    {
      type = "conditional";
      conditions = [
        {
          entity = helper;
          state = "on";
        }
      ];
      card = {
        type = "vertical-stack";
        cards = [
          {
            type = "markdown";
            content = "${emoji} **${label}:** Feeder **feed-${key}** ${message}";
          }
          {
            type = "button";
            name = "Dismiss ${name} ${shortLabel} Alert";
            icon = "mdi:bell-off";
            tap_action = {
              action = "call-service";
              service = "input_boolean.turn_off";
              target = {
                entity_id = helper;
              };
            };
          }
        ];
      };
    };
  mkAlertCards =
    name:
    map (alert: mkAlertCard (alert // { inherit name; })) [
      {
        helperSuffix = "low_food";
        emoji = "⚠️";
        label = "Low Food Warning";
        shortLabel = "Low Food";
        message = "reported LOW_FOOD. Please refill the food hopper.";
      }
      {
        helperSuffix = "jam";
        emoji = "🚨";
        label = "Feed Jam Alert";
        shortLabel = "Jam";
        message = "reported a grain jam! Please inspect and clear the dispenser.";
      }
    ];
in
{
  title = "Pets";
  path = "pets";
  icon = "mdi:paw";
  cards = [
    (mkCameraCard "Library" "camera.library")
    {
      type = "horizontal-stack";
      cards = map mkPetCard pets;
    }
    {
      type = "vertical-stack";
      cards = lib.concatMap (pet: mkAlertCards pet.name) pets;
    }
  ];
}
