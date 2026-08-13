{ lib }:
let
  # PETLIBRO PLAF301 feeders, redirected from Petlibro's own cloud to
  # newyork's local mosquitto broker instead -- see ~/projects/
  # feeder-jailbreak (topic layout and command/event JSON schemas, both
  # reverse-engineered via firmware disassembly, not documented by Petlibro
  # anywhere) and hosts/newyork/modules/services/mosquitto/default.nix (the
  # broker-side ACL these devices actually authenticate against). HA
  # connects to that same broker as `frigate` (readwrite on everything, see
  # the age.secrets comment below), so no separate credential is needed
  # here -- these entities just add topics on top of that existing
  # connection. `feed-extra` (homelab/hosts.nix has its MAC) is excluded:
  # no device ID/credentials have been captured for it yet, unlike the
  # three below.
  feeders = [
    {
      name = "feed-jem";
      deviceId = "AF0601030298F0C1320D";
    }
    {
      name = "feed-willow";
      deviceId = "AF0600310007DF0B19802Q";
    }
    {
      name = "feed-fern";
      deviceId = "AF06013A96214C47U";
    }
  ];
  feederDevice =
    { name, deviceId }:
    {
      identifiers = [ "plaf301_${deviceId}" ];
      inherit name;
      manufacturer = "PETLIBRO";
      model = "PLAF301";
    };
  # "feed-jem" -> "feed_jem", matching HA's own slugification of entity
  # names -- used to reference the paired input_number helper (below) from
  # inside the Feed Now button's payload_press template by a name we
  # control directly, rather than guessing how HA would slug it.
  feederKey = name: builtins.replaceStrings [ "-" ] [ "_" ] name;
  # dl/PLAF301/{deviceId}/device/{ntp,ota,config,event,service,system}/{sub,post}
  # -- `sub` topics are commands published TO the device, `post` topics are
  # the device reporting TO us. `heart`/`event` aren't in that six-name set
  # (heartbeats and structured events get their own leaves), confirmed by
  # direct observation in feeder-jailbreak/FINDINGS.md's live session
  # capture rather than by the naming pattern above.
  feederTopic = deviceId: leaf: "dl/PLAF301/${deviceId}/device/${leaf}";
  # Every feeder multiplexes many event kinds onto one `event/post` topic
  # (GRAIN_OUTPUT_EVENT, WAREHOUSE_DOOR_EVENT, PET_IDENTIFY_EVENT, ...) --
  # an entity that only cares about one kind renders `this.state` for every
  # other kind, preserving its current state instead of rendering `None`
  # (which HA parses as an invalid value, resetting the entity to `unknown`).
  feederBinarySensors =
    { name, deviceId }:
    [
      {
        name = "Online";
        unique_id = "${deviceId}_online";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "heart/post";
        value_template = "{{ 'ON' if value_json.cmd == 'HEARTBEAT' else 'OFF' }}";
        payload_on = "ON";
        payload_off = "OFF";
        # Heartbeats land every 60-70s (feeder-jailbreak/FINDINGS.md) --
        # 150s covers one dropped beat before flagging offline, without
        # being so long a real outage takes minutes to notice.
        expire_after = 150;
        device_class = "connectivity";
      }
      {
        # execStep's GRAIN_BLOCKING/GRAIN_BLOCKED/GRAIN_STUCK values
        # (mqtt_command_reference.md's "Common Error/Status Strings") are
        # jam states reported on the same GRAIN_OUTPUT_EVENT stream "Last
        # Fed" below already reads -- unlike the ERROR_EVENT-sourced
        # sensors further down, this one gets a real binary on/off because
        # its clear condition is just as well-documented as its set
        # condition (a normal GRAIN_END/finished completion).
        name = "Feed Jam";
        unique_id = "${deviceId}_feed_jam";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'GRAIN_OUTPUT_EVENT' -%}
            {%- if value_json.execStep in ['GRAIN_BLOCKING', 'GRAIN_BLOCKED', 'GRAIN_STUCK'] -%}
              {{- 'ON' -}}
            {%- elif value_json.execStep == 'GRAIN_END' or value_json.finished -%}
              {{- 'OFF' -}}
            {%- else -%}
              {{- this.state | upper if (this is defined and this.state in ['on', 'off']) else 'OFF' -}}
            {%- endif -%}
          {%- else -%}
            {{- this.state | upper if (this is defined and this.state in ['on', 'off']) else 'OFF' -}}
          {%- endif -%}
        '';
        payload_on = "ON";
        payload_off = "OFF";
        device_class = "problem";
      }
    ];
  feederSensors =
    { name, deviceId }:
    [
      {
        name = "Signal Strength";
        unique_id = "${deviceId}_rssi";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "heart/post";
        value_template = "{{ value_json.rssi }}";
        device_class = "signal_strength";
        unit_of_measurement = "dBm";
        state_class = "measurement";
        entity_category = "diagnostic";
      }
      {
        name = "Last Fed";
        unique_id = "${deviceId}_last_fed";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        # The device doesn't put its own wall-clock time on this event, so
        # this is "when HA saw the finish" rather than "when the device
        # says it finished" -- close enough given events arrive within a
        # second or two of the real thing. Same caveat applies to every
        # other now().isoformat()-based sensor below.
        value_template = ''
          {%- if value_json.cmd == 'GRAIN_OUTPUT_EVENT' and value_json.finished -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
      }
      {
        # PET_IDENTIFY_EVENT fires when an RFID collar comes into range.
        # State is the raw tag, not a pet name -- there's no memberId ->
        # pet-name mapping anywhere in this config (ADD_OR_UPDATE_RFID_SERVICE,
        # which would set one, has never been sent), so calibrationTag is
        # the only thing guaranteed to mean something.
        name = "Pet Last Scanned";
        unique_id = "${deviceId}_last_scanned";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'PET_IDENTIFY_EVENT' -%}
            {{- value_json.calibrationTag -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'PET_IDENTIFY_EVENT' -%}
            {{- {'member_id': value_json.memberId} | tojson -}}
          {%- elif this is defined and 'member_id' in this.attributes -%}
            {{- {'member_id': this.attributes.member_id} | tojson -}}
          {%- else -%}
            {{- {} | tojson -}}
          {%- endif -%}
        '';
        icon = "mdi:paw";
      }
      {
        # MACHINE_INFRARED_EVENT: the bowl's break-beam/presence sensor.
        # FINDINGS.md only confirms *that* this fires, not any field names
        # inside it (unlike the events above, which were seen with full
        # payloads) -- so this reports "when it last fired" rather than
        # guessing at a boolean field that isn't documented anywhere.
        name = "Bowl Activity";
        unique_id = "${deviceId}_bowl_activity";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'MACHINE_INFRARED_EVENT' -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
        entity_category = "diagnostic";
      }
      {
        # ERROR_EVENT covers everything in mqtt_command_reference.md's
        # "Common Error/Status Strings" that isn't the feed jam above --
        # LOW_FOOD, LOW_BATTERY, BARN_OPEN_DOOR_ERROR/BARN_CLOSE_DOOR_ERROR,
        # OFFLINE/NETWORK_*. One generic "last error" sensor instead of a
        # binary_sensor per condition: none of these have a documented
        # clear/resolved counterpart event the way the feed jam does, so a
        # binary_sensor here could only ever latch on and never honestly
        # turn back off. This just reports the most recent one instead of
        # claiming to know current state.
        name = "Last Error";
        unique_id = "${deviceId}_last_error";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'ERROR_EVENT' -%}
            {{- value_json.errorMsg -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'ERROR_EVENT' -%}
            {{- {'error_code': value_json.errorCode, 'at': now().isoformat()} | tojson -}}
          {%- elif this is defined and 'error_code' in this.attributes -%}
            {{- {'error_code': this.attributes.error_code, 'at': this.attributes.at} | tojson -}}
          {%- else -%}
            {{- {} | tojson -}}
          {%- endif -%}
        '';
        icon = "mdi:alert";
        entity_category = "diagnostic";
      }
      {
        # DEVICE_START_EVENT fires once per boot -- useful mainly to
        # confirm an unexpected reboot happened at all (restartReason,
        # powerCycle) rather than anything ongoing.
        name = "Last Boot";
        unique_id = "${deviceId}_last_boot";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'DEVICE_START_EVENT' -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'DEVICE_START_EVENT' -%}
            {{- {
              'hardware_version': value_json.hardwareVersion,
              'software_version': value_json.softwareVersion,
              'power_cycle': value_json.powerCycle,
              'restart_reason': value_json.restartReason,
            } | tojson -}}
          {%- elif this is defined and 'hardware_version' in this.attributes -%}
            {{- {
              'hardware_version': this.attributes.hardware_version,
              'software_version': this.attributes.software_version,
              'power_cycle': this.attributes.power_cycle,
              'restart_reason': this.attributes.restart_reason,
            } | tojson -}}
          {%- else -%}
            {{- {} | tojson -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
        entity_category = "diagnostic";
      }
      {
        # Catch-all for ATTR_GET_SERVICE/DEVICE_PROPERTIES_SERVICE responses
        # (both land on service/post, the "post" counterpart of the
        # service/sub commands below) -- unlike event/post's fixed set of
        # event kinds, these two return whatever fields the firmware
        # decides to report, which isn't practical to pick apart field by
        # field in Nix. State is just the ack code; the full response body
        # is in the state attribute.
        name = "Last Service Response";
        unique_id = "${deviceId}_last_service_response";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "service/post";
        value_template = "{{ value_json.code if (value_json.code is defined) else (this.state if this is defined else 'unknown') }}";
        json_attributes_topic = feederTopic deviceId "service/post";
        json_attributes_template = "{{ value_json | tojson if (value_json is defined and value_json) else (this.attributes | tojson if this is defined else {} | tojson) }}";
        icon = "mdi:message-reply-text";
        entity_category = "diagnostic";
      }
      {
        # Response to TRIGGER_DEVICE_LOG_REPORT_SERVICE (button below) --
        # DEVICE_LOG_REPORT_EVENT on event/post, structured diagnostic data
        # (DNS servers, connection latency per FINDINGS.md). Same
        # whole-payload-as-attributes approach as Last Service Response
        # above, for the same reason (undocumented field set).
        name = "Last Diagnostic Log";
        unique_id = "${deviceId}_last_diagnostic_log";
        device = feederDevice { inherit name deviceId; };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'DEVICE_LOG_REPORT_EVENT' -%}
            {{- now().isoformat() -}}
          {%- else -%}
            {{- this.state if this is defined else 'unknown' -}}
          {%- endif -%}
        '';
        json_attributes_topic = feederTopic deviceId "event/post";
        json_attributes_template = ''
          {%- if value_json.cmd == 'DEVICE_LOG_REPORT_EVENT' -%}
            {{- value_json | tojson -}}
          {%- else -%}
            {{- this.attributes | tojson if this is defined else {} | tojson -}}
          {%- endif -%}
        '';
        device_class = "timestamp";
        entity_category = "diagnostic";
      }
    ];
  feederCovers =
    { name, deviceId }:
    [
      {
        # `cover`/device_class `door` fits the lid better than a plain
        # switch: SWITCH_DOOR_SERVICE's own closeDoorTimeSec auto-close
        # timer means the device flips itself back to closed on its own a
        # few seconds after opening (confirmed live, feeder-jailbreak/
        # FINDINGS.md "2026-08-12 (latest)"), and WAREHOUSE_DOOR_EVENT
        # reports that self-close the same as a commanded one -- so this
        # entity's state tracks reality either way, not just what HA asked
        # for.
        name = "Lid";
        unique_id = "${deviceId}_lid";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_open = builtins.toJSON {
          cmd = "SWITCH_DOOR_SERVICE";
          barnDoorState = 1;
        };
        payload_close = builtins.toJSON {
          cmd = "SWITCH_DOOR_SERVICE";
          barnDoorState = 0;
        };
        state_topic = feederTopic deviceId "event/post";
        value_template = ''
          {%- if value_json.cmd == 'WAREHOUSE_DOOR_EVENT' -%}
            {{- 'open' if value_json.triggerType == 'COVER_OPEN' else 'closed' -}}
          {%- else -%}
            {{- this.state if this is defined else 'closed' -}}
          {%- endif -%}
        '';
        device_class = "door";
      }
    ];
  # Text/number/time helpers that exist purely so a button can read a
  # value at press time -- MQTT button/select/switch/number entities can
  # each only publish their own single fixed-shape payload, so anything
  # needing more than one field (RFID add, WiFi change, the feeding
  # schedule) has to pull its extra fields from a paired helper the same
  # way Feed Now already does for grainNum.
  feederTextHelpers =
    { name, deviceId }:
    let
      key = feederKey name;
    in
    [
      (lib.nameValuePair "${key}_rfid_member_id" {
        name = "${name} RFID Member ID";
        icon = "mdi:identifier";
      })
      (lib.nameValuePair "${key}_rfid_calibration_tag" {
        name = "${name} RFID Calibration Tag";
        icon = "mdi:tag";
      })
      # 7-char Mon-Sun bitmask ("1111111" = every day) -- a text field
      # matching DEVICE_FEEDING_PLAN_SERVICE's own wire format directly is
      # simpler than building seven separate day-toggle helpers for one
      # rarely-changed setting.
      (lib.nameValuePair "${key}_schedule_repeat_days" {
        name = "${name} Schedule Repeat Days";
        icon = "mdi:calendar-week";
        pattern = "^[01]{7}$";
      })
      (lib.nameValuePair "${key}_wifi_ssid" {
        name = "${name} WiFi SSID (caution)";
        icon = "mdi:wifi";
      })
      (lib.nameValuePair "${key}_wifi_password" {
        name = "${name} WiFi Password (caution)";
        mode = "password";
        icon = "mdi:wifi-lock";
      })
    ];
  feederNumberHelpers =
    { name, deviceId }:
    let
      key = feederKey name;
    in
    [
      (lib.nameValuePair "${key}_feed_amount" {
        name = "${name} Feed Amount";
        min = 1;
        max = 10;
        step = 1;
        initial = 1;
        icon = "mdi:bowl-mix";
        unit_of_measurement = "portions";
      })
      (lib.nameValuePair "${key}_schedule_grain_amount" {
        name = "${name} Schedule Grain Amount";
        min = 1;
        max = 10;
        step = 1;
        initial = 1;
        icon = "mdi:bowl-mix";
        unit_of_measurement = "portions";
      })
    ];
  feederTimeHelpers =
    { name, deviceId }:
    [
      (lib.nameValuePair "${feederKey name}_schedule_time" {
        name = "${name} Schedule Time";
        has_time = true;
        has_date = false;
      })
    ];
  # Individual on/off toggles for the handful of ATTR_SET_SERVICE fields
  # (mqtt_command_reference.md's ~30-field bulk setter) that are actually
  # meant for regular use, rather than one giant form for all of them --
  # motor PWM duty cycles, stall-current thresholds, and the rest are
  # calibration parameters, not user-facing settings, and aren't exposed
  # here.
  feederSwitches =
    { name, deviceId }:
    let
      attrSwitch =
        {
          key,
          label,
          field,
          icon,
        }:
        {
          name = label;
          unique_id = "${deviceId}_${key}";
          device = feederDevice { inherit name deviceId; };
          command_topic = feederTopic deviceId "service/sub";
          payload_on = builtins.toJSON {
            cmd = "ATTR_SET_SERVICE";
            ${field} = 1;
          };
          payload_off = builtins.toJSON {
            cmd = "ATTR_SET_SERVICE";
            ${field} = 0;
          };
          # ATTR_SET_SERVICE's ack (Last Service Response) only confirms
          # the write was received, not the new value, and ATTR_PUSH_EVENT
          # bundles the device's *entire* config schema per push -- not
          # worth parsing out one field from that just to avoid assuming
          # the command we sent took effect.
          optimistic = true;
          inherit icon;
        };
    in
    map attrSwitch [
      {
        key = "child_lock";
        label = "Child Lock";
        field = "childLockSwitch";
        icon = "mdi:lock";
      }
      {
        key = "sound";
        label = "Sound";
        field = "soundSwitch";
        icon = "mdi:volume-high";
      }
      {
        key = "disable_buttons";
        label = "Disable Physical Buttons";
        field = "disableHardwareButton";
        icon = "mdi:gesture-tap-button";
      }
      {
        key = "screen_display";
        label = "Screen Display";
        field = "enableScreenDisplay";
        icon = "mdi:monitor";
      }
    ];
  feederNumbers =
    { name, deviceId }:
    [
      {
        name = "Auto-Close Timer";
        unique_id = "${deviceId}_close_door_time";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        command_template = "{{ {'cmd': 'ATTR_SET_SERVICE', 'closeDoorTimeSec': value | int} | tojson }}";
        min = 0;
        max = 120;
        step = 1;
        unit_of_measurement = "s";
        optimistic = true;
        icon = "mdi:timer-outline";
      }
    ];
  feederSelects =
    { name, deviceId }:
    [
      {
        name = "Display Scene";
        unique_id = "${deviceId}_display_scene";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        command_template = "{{ {'cmd': 'DISPLAY_MATRIX_SERVICE', 'displayScene': value} | tojson }}";
        options = [
          "PET_NAME"
          "PRODUCT_TEST"
          "DEFAULT_HELLO"
        ];
        optimistic = true;
        icon = "mdi:image-text";
      }
      {
        # Ghidra/radare2-confirmed (stock_backup_8M_sanitized.bin, ARM
        # Thumb-2, ATTR_SET_SERVICE handler): coverCloseSpeed isn't numeric
        # at all despite mqtt_command_reference.md's "int" description --
        # it's a 3-way string match against literal "FAST", then "SLOW",
        # then "MEDIUM" (in that fallback order; internally mapped to
        # 0/2/1 respectively, though that encoding is invisible to the
        # JSON payload). Any other string is silently ignored, the same
        # "accepted but no-op" failure mode as an unrecognized
        # barnDoorState value.
        name = "Close Speed";
        unique_id = "${deviceId}_close_speed";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        command_template = "{{ {'cmd': 'ATTR_SET_SERVICE', 'coverCloseSpeed': value} | tojson }}";
        options = [
          "SLOW"
          "MEDIUM"
          "FAST"
        ];
        optimistic = true;
        icon = "mdi:speedometer";
      }
    ];
  feederButtons =
    { name, deviceId }:
    let
      key = feederKey name;
    in
    [
      {
        name = "Feed Now";
        unique_id = "${deviceId}_feed_now";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        # Unlike the fixed payloads elsewhere in this file, this one has to
        # be a live template (not builtins.toJSON at build time) -- it
        # reads the paired input_number helper's *current* value each time
        # the button is pressed, defaulting to 1 portion if that helper is
        # ever unknown/non-numeric (e.g. right after a HA restart, before
        # its state has been restored).
        payload_press = ''
          {{ {'cmd': 'MANUAL_FEEDING_SERVICE', 'grainNum': states('input_number.${key}_feed_amount') | int(1)} | tojson }}
        '';
      }
      {
        name = "Set Feeding Schedule";
        unique_id = "${deviceId}_feeding_plan";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        # channelPlanNum/planId/audioTimes aren't exposed as their own
        # helpers -- one HA-managed plan slot with a fixed id and a
        # reasonable default call-to-eat repeat count covers the normal
        # "feed at this time, this much, on these days" case without
        # needing three more input helpers per feeder.
        payload_press = ''
          {{ {
            'cmd': 'DEVICE_FEEDING_PLAN_SERVICE',
            'channelPlanNum': 1,
            'planId': 'ha_plan',
            'grainNum': states('input_number.${key}_schedule_grain_amount') | int(1),
            'executionTime': states('input_datetime.${key}_schedule_time')[:5],
            'repeatDay': states('input_text.${key}_schedule_repeat_days'),
            'audioTimes': 2,
            'syncTime': as_timestamp(now()) | int,
          } | tojson }}
        '';
        icon = "mdi:calendar-clock";
      }
      {
        name = "Refresh Settings";
        unique_id = "${deviceId}_attr_get";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "ATTR_GET_SERVICE"; };
        icon = "mdi:refresh";
        entity_category = "diagnostic";
      }
      {
        name = "Refresh Device Info";
        unique_id = "${deviceId}_device_properties";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "DEVICE_PROPERTIES_SERVICE"; };
        icon = "mdi:information-outline";
        entity_category = "diagnostic";
      }
      {
        name = "Start RFID Discovery";
        unique_id = "${deviceId}_rfid_discovery_start";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "DISCOVERY_RFID_SERVICE"; };
        icon = "mdi:card-search";
      }
      {
        name = "Stop RFID Discovery";
        unique_id = "${deviceId}_rfid_discovery_stop";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "DISCOVERY_STOP_SERVICE"; };
        icon = "mdi:card-search-outline";
      }
      {
        # Reads the two RFID input_text helpers (config.input_text below)
        # at press time -- same live-template approach as Feed Now, for the
        # same reason (a button can't take parameters of its own).
        name = "Add/Update RFID Tag";
        unique_id = "${deviceId}_rfid_add";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = ''
          {{ {'cmd': 'ADD_OR_UPDATE_RFID_SERVICE', 'memberId': states('input_text.${key}_rfid_member_id'), 'calibrationTag': states('input_text.${key}_rfid_calibration_tag')} | tojson }}
        '';
        icon = "mdi:card-plus";
      }
      {
        name = "Delete RFID Tag";
        unique_id = "${deviceId}_rfid_delete";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = ''
          {{ {'cmd': 'DEL_RFID_SERVICE', 'memberId': states('input_text.${key}_rfid_member_id')} | tojson }}
        '';
        icon = "mdi:card-remove";
      }
      {
        name = "Unbind Pet";
        unique_id = "${deviceId}_unbind_pet";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = ''
          {{ {'cmd': 'UNBIND_PET_SERVICE', 'memberId': states('input_text.${key}_rfid_member_id')} | tojson }}
        '';
        icon = "mdi:account-off";
      }
      {
        name = "Reconnect WiFi";
        unique_id = "${deviceId}_wifi_reconnect";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "WIFI_RECONNECT_SERVICE"; };
        icon = "mdi:wifi-refresh";
        entity_category = "diagnostic";
      }
      {
        # CAUTION (mqtt_command_reference.md): wrong credentials here can
        # knock the device off the network entirely, with no remote way
        # back short of re-provisioning it from scratch. Not disabled, but
        # not made any easier to hit by accident than typing into the two
        # WiFi input_text helpers above and then pressing this specific
        # button.
        name = "Change WiFi (Caution)";
        unique_id = "${deviceId}_wifi_change";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = ''
          {{ {'cmd': 'WIFI_CHANGE_SERVICE', 'wifiSsid': states('input_text.${key}_wifi_ssid'), 'wifiPassword': states('input_text.${key}_wifi_password')} | tojson }}
        '';
        icon = "mdi:alert-octagon";
      }
      {
        name = "Run Self-Test";
        unique_id = "${deviceId}_function_test";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "DEVICE_FUNCTION_TEST_SERVICE"; };
        icon = "mdi:test-tube";
        entity_category = "diagnostic";
      }
      {
        name = "Request Diagnostic Log";
        unique_id = "${deviceId}_log_report";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "TRIGGER_DEVICE_LOG_REPORT_SERVICE"; };
        icon = "mdi:file-document-outline";
        entity_category = "diagnostic";
      }
      {
        # No documented on/off field -- mqtt_command_reference.md shows a
        # bare {"cmd": "DEVICE_PRINT_LOG_SWITCH_SERVICE"} with no params at
        # all, so this is modeled as a stateless toggle rather than a
        # switch since there's no evidence it takes a specific target
        # state.
        name = "Toggle Debug Logging";
        unique_id = "${deviceId}_print_log_switch";
        device = feederDevice { inherit name deviceId; };
        command_topic = feederTopic deviceId "service/sub";
        payload_press = builtins.toJSON { cmd = "DEVICE_PRINT_LOG_SWITCH_SERVICE"; };
        icon = "mdi:file-document-edit-outline";
        entity_category = "diagnostic";
      }
    ];
in
{
  input_number = lib.listToAttrs (lib.concatMap feederNumberHelpers feeders);
  input_text = lib.listToAttrs (lib.concatMap feederTextHelpers feeders);
  input_datetime = lib.listToAttrs (lib.concatMap feederTimeHelpers feeders);
  mqtt = {
    binary_sensor = lib.concatMap feederBinarySensors feeders;
    sensor = lib.concatMap feederSensors feeders;
    cover = lib.concatMap feederCovers feeders;
    switch = lib.concatMap feederSwitches feeders;
    number = lib.concatMap feederNumbers feeders;
    select = lib.concatMap feederSelects feeders;
    button = lib.concatMap feederButtons feeders;
  };
}
