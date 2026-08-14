{ }:
{
  automation = [
    {
      alias = "Frigate alert notification";
      description = "Push notification when Frigate creates a new alert review item.";
      trigger = [
        {
          platform = "mqtt";
          topic = "frigate/reviews";
        }
      ];
      # Frigate publishes "new", "update", and "end" messages over a review
      # item's lifetime. A review item's severity is NOT fixed when it is
      # created: Frigate frequently opens an item as "detection" and only
      # upgrades it to "alert" in a later "update" message (once the object
      # is confirmed / enters an alert zone). Filtering on
      # `type == 'new' and severity == 'alert'` therefore silently drops
      # every alert that escalates after creation -- which is most of them.
      #
      # Instead, fire once on the transition INTO alert severity: any
      # non-"end" message where severity just became "alert" (before != alert,
      # after == alert). This catches both alerts that start as alerts and
      # alerts promoted from detection, while the `tag` (review id) below
      # dedupes any repeats.
      condition = [
        {
          condition = "template";
          value_template = ''
            {{ trigger.payload_json['type'] != 'end'
               and trigger.payload_json['after']['severity'] == 'alert'
               and trigger.payload_json['before']['severity'] != 'alert' }}
          '';
        }
      ];
      action = [
        {
          service = "notify.mobile_app_pixel_10";
          data = {
            title = "Frigate Alert";
            message = "{{ trigger.payload_json['after']['data']['objects'] | sort | join(', ') | title }} detected on {{ trigger.payload_json['after']['camera'] }}";
            data = {
              # Relative path, not the public https URL. The companion app
              # downloads the notification image before it displays the
              # notification, so a slow fetch delays the whole alert. A
              # relative /api/... path is resolved against whichever HA URL
              # the app is already connected to (the internal LAN URL when
              # home), avoiding the WAN -> caddy(newyork) -> HA(dubai) ->
              # frigate(pyongyang) round trip the hard-coded external URL
              # forced on every notification.
              image = "/api/frigate/notifications/{{ trigger.payload_json['after']['id'] }}/thumbnail.jpg";
              tag = "{{ trigger.payload_json['after']['id'] }}";

              # Delivery priority. Without these, the push is sent to FCM at
              # normal priority, which Android is free to hold until the
              # device next leaves Doze -- which is why alerts "arrive" all
              # at once the moment the phone is unlocked. Exempting the
              # companion app from battery optimization does NOT fix this:
              # the priority is chosen by the *sender*, not the app.
              # `priority: high` + `ttl: 0` tells FCM to wake the device and
              # deliver now, or drop it rather than queue it. This is the
              # same class of push messaging apps use, and it is what the
              # companion docs prescribe for notifications that must ring
              # before the screen is turned on.
              ttl = 0;
              priority = "high";

              # Dedicated notification channel so these can be given their
              # own importance/sound without affecting every other HA
              # notification. NOTE: on Android 8+, a channel's importance is
              # fixed the FIRST time the channel is seen and can afterwards
              # only be *lowered* -- so this must be a channel name that has
              # not been used before (the default is "General"). If the
              # importance ever needs raising again, change this string or
              # adjust the channel in Android's notification settings.
              channel = "Frigate Alerts";
              importance = "high";
            };
          };
        }
      ];
      mode = "single";
    }
    {
      alias = "Feeder low food persistent notification";
      description = "Create a persistent notification when a pet feeder reports LOW_FOOD.";
      trigger = [
        {
          platform = "state";
          entity_id = [
            "sensor.feed_jem_last_error"
            "sensor.feed_willow_last_error"
            "sensor.feed_fern_last_error"
          ];
          to = "LOW_FOOD";
        }
      ];
      action = [
        {
          service = "persistent_notification.create";
          data = {
            title = "Feeder Low Food Alert";
            message = "{{ state_attr(trigger.entity_id, 'friendly_name') | default(trigger.entity_id) }} reported LOW_FOOD!";
            notification_id = "{{ trigger.entity_id | replace('sensor.', '') | replace('_last_error', '') }}_low_food";
          };
        }
      ];
      mode = "parallel";
    }
    {
      alias = "Feeder feed jam persistent notification";
      description = "Create or dismiss a persistent notification when a pet feeder detects or clears a feed jam.";
      trigger = [
        {
          platform = "state";
          entity_id = [
            "binary_sensor.feed_jem_feed_jam"
            "binary_sensor.feed_willow_feed_jam"
            "binary_sensor.feed_fern_feed_jam"
          ];
          to = "on";
          id = "jam_detected";
        }
        {
          platform = "state";
          entity_id = [
            "binary_sensor.feed_jem_feed_jam"
            "binary_sensor.feed_willow_feed_jam"
            "binary_sensor.feed_fern_feed_jam"
          ];
          to = "off";
          id = "jam_cleared";
        }
      ];
      action = [
        {
          choose = [
            {
              conditions = [
                {
                  condition = "trigger";
                  id = [ "jam_detected" ];
                }
              ];
              sequence = [
                {
                  service = "persistent_notification.create";
                  data = {
                    title = "Feeder Jam Alert";
                    message = "{{ state_attr(trigger.entity_id, 'friendly_name') | default(trigger.entity_id) }} is jammed!";
                    notification_id = "{{ trigger.entity_id | replace('binary_sensor.', '') | replace('_feed_jam', '') }}_jam";
                  };
                }
              ];
            }
            {
              conditions = [
                {
                  condition = "trigger";
                  id = [ "jam_cleared" ];
                }
              ];
              sequence = [
                {
                  service = "persistent_notification.dismiss";
                  data = {
                    notification_id = "{{ trigger.entity_id | replace('binary_sensor.', '') | replace('_feed_jam', '') }}_jam";
                  };
                }
              ];
            }
          ];
        }
      ];
      mode = "parallel";
    }
  ];
}
