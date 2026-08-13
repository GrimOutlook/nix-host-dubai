{ }:
let
  # House coordinates, shared by every NWS API call below (the alerts feed
  # and the forecast feed) so they can't drift out of sync with each other.
  nwsLat = "34.7608002429598";
  nwsLon = "-86.69216641164486";
  # NWS's forecast API is keyed by a grid office + x/y cell, not lat/lon
  # directly -- these came from a one-time lookup against
  # https://api.weather.gov/points/${nwsLat},${nwsLon} and won't change for
  # a fixed point, so it's cheaper to hardcode them than to chain two REST
  # calls (Home Assistant's rest sensor can't template its resource URL
  # from another entity's state).
  nwsGridOffice = "HUN";
  nwsGridX = "59";
  nwsGridY = "44";
  # NWS asks for an identifying User-Agent on every request (no API key
  # needed) -- an empty/generic one gets rate limited or blocked, so this is
  # the address recommended in their docs (any contact string works, it's
  # just for their abuse reports).
  nwsUserAgent = "Home Assistant (dominic.j.grimaldi@gmail.com)";
  # Shared by the weather entity's current-condition template and each
  # forecast period below -- maps NWS's own icon vocabulary
  # (https://api.weather.gov/icons) to Home Assistant's weather condition
  # enum. `skc`/`few` (clear/few clouds) are the only codes HA distinguishes
  # by day vs night (sunny/clear-night); everything else maps the same
  # regardless of daylight, so they're handled separately from this map.
  nwsConditionMap = ''
    {% set code_map = {
      'sct': 'partlycloudy', 'bkn': 'cloudy', 'ovc': 'cloudy',
      'wind_skc': 'windy', 'wind_few': 'windy', 'wind_sct': 'windy-variant',
      'wind_bkn': 'windy-variant', 'wind_ovc': 'windy-variant',
      'snow': 'snowy', 'rain_snow': 'snowy-rainy', 'rain_sleet': 'snowy-rainy',
      'snow_sleet': 'snowy-rainy', 'fzra': 'snowy-rainy', 'rain_fzra': 'snowy-rainy',
      'snow_fzra': 'snowy-rainy', 'sleet': 'snowy-rainy',
      'rain': 'rainy', 'rain_showers': 'rainy', 'rain_showers_hi': 'rainy',
      'tsra': 'lightning-rainy', 'tsra_sct': 'lightning-rainy', 'tsra_hi': 'lightning-rainy',
      'tornado': 'exceptional', 'hurricane': 'exceptional', 'tropical_storm': 'exceptional',
      'dust': 'exceptional', 'smoke': 'exceptional', 'haze': 'exceptional',
      'hot': 'sunny', 'cold': 'snowy', 'blizzard': 'snowy', 'fog': 'fog'
    } %}
    {% macro nws_condition(period) %}
      {%- set code = period.icon.split('/')[-1].split('?')[0].split(',')[0] -%}
      {%- if code in ['skc', 'few'] -%}
        {{ 'sunny' if period.isDaytime else 'clear-night' }}
      {%- else -%}
        {{ code_map.get(code, 'partlycloudy') }}
      {%- endif -%}
    {% endmacro %}
  '';
  # Shared Jinja macro to gather NWS's official Heat Index (°F) directly from
  # NWS's gridpoints API feed (sensor.nws_gridpoints), falling back to NWS's
  # apparentTemperature if heatIndex is null (e.g. cold weather).
  nwsHeatIndexMacro = ''
    {% macro nws_heat_index(idx=0) %}
      {%- set hi_attr = state_attr('sensor.nws_gridpoints', 'heatIndex') -%}
      {%- set app_attr = state_attr('sensor.nws_gridpoints', 'apparentTemperature') -%}
      {%- set hi_val = (hi_attr.values[idx].value) if (hi_attr and hi_attr.values and hi_attr.values | length > idx and hi_attr.values[idx].value is not none) else None -%}
      {%- set app_val = (app_attr.values[idx].value) if (app_attr and app_attr.values and app_attr.values | length > idx and app_attr.values[idx].value is not none) else None -%}
      {%- set c_val = hi_val if hi_val is not none else app_val -%}
      {%- if c_val is not none -%}
        {{- (c_val * 9 / 5 + 32) | round(1) -}}
      {%- else -%}
        {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
        {{- (periods[idx].temperature) if (periods and periods | length > idx) else None -}}
      {%- endif -%}
    {% endmacro %}
  '';
in
{
  recorder.exclude.entities = [
    "sensor.nws_forecast"
    "sensor.nws_hourly_forecast"
    "sensor.nws_gridpoints"
  ];

  sensor = [
    {
      # National Weather Service active-alerts feed for the house's
      # coordinates. NWS asks for an identifying User-Agent on every
      # request (no API key needed) -- an empty/generic one gets rate
      # limited or blocked, so this is the address recommended in their
      # docs (any contact string works, it's just for their abuse
      # reports).
      platform = "rest";
      name = "NWS Active Alerts";
      resource = "https://api.weather.gov/alerts/active?point=${nwsLat},${nwsLon}";
      method = "GET";
      headers = {
        User-Agent = nwsUserAgent;
        Accept = "application/geo+json";
      };
      # Value is just a count; the binary_sensor below re-parses the
      # attribute for the actual event names.
      value_template = "{{ value_json.features | length }}";
      json_attributes = [ "features" ];
      scan_interval = 60;
    }
    {
      # Feeds the "NWS" template weather entity below (config.weather) --
      # NWS's own 12-hour period forecast (day/night pairs) for the house's
      # coordinates. This is the same data https://forecast.weather.gov
      # itself is built from.
      platform = "rest";
      name = "NWS Forecast";
      resource = "https://api.weather.gov/gridpoints/${nwsGridOffice}/${nwsGridX},${nwsGridY}/forecast";
      method = "GET";
      headers = {
        User-Agent = nwsUserAgent;
        Accept = "application/geo+json";
      };
      # The periods array is what actually matters; the sensor's own
      # state is just "when was this last generated by NWS" so it's
      # something other than the whole JSON blob.
      value_template = "{{ value_json.properties.updateTime }}";
      device_class = "timestamp";
      json_attributes_path = "$.properties";
      json_attributes = [ "periods" ];
      # NWS regenerates this forecast a handful of times a day, not
      # continuously -- polling every 30m is plenty and stays well clear
      # of any abuse-rate concerns.
      scan_interval = 1800;
    }
    {
      # Same forecast, but NWS's hourly periods (unlike the 12-hour ones
      # above) carry relativeHumidity/dewpoint -- this exists purely to
      # feed the weather entity's humidity_template, which the `template`
      # integration's schema requires even though nothing on this
      # dashboard displays it directly.
      platform = "rest";
      name = "NWS Hourly Forecast";
      resource = "https://api.weather.gov/gridpoints/${nwsGridOffice}/${nwsGridX},${nwsGridY}/forecast/hourly";
      method = "GET";
      headers = {
        User-Agent = nwsUserAgent;
        Accept = "application/geo+json";
      };
      value_template = "{{ value_json.properties.updateTime }}";
      device_class = "timestamp";
      json_attributes_path = "$.properties";
      json_attributes = [ "periods" ];
      scan_interval = 1800;
    }
    {
      # Raw gridpoint forecast from NWS. Sourced directly from
      # https://api.weather.gov/gridpoints/HUN/59,44 to gather NWS's own
      # official heatIndex and apparentTemperature forecast data.
      platform = "rest";
      name = "NWS Gridpoints";
      resource = "https://api.weather.gov/gridpoints/${nwsGridOffice}/${nwsGridX},${nwsGridY}";
      method = "GET";
      headers = {
        User-Agent = nwsUserAgent;
        Accept = "application/geo+json";
      };
      value_template = "{{ value_json.properties.updateTime }}";
      device_class = "timestamp";
      json_attributes_path = "$.properties";
      json_attributes = [
        "heatIndex"
        "apparentTemperature"
      ];
      scan_interval = 1800;
    }
  ];

  template = [
    {
      sensor = [
        {
          name = "NWS Heat Index";
          default_entity_id = "sensor.nws_heat_index";
          unit_of_measurement = "°F";
          device_class = "temperature";
          state_class = "measurement";
          icon = "mdi:thermometer-lines";
          state = ''
            ${nwsHeatIndexMacro}
            {{- nws_heat_index(0) | default('unavailable') -}}
          '';
          availability = "{{ states('sensor.nws_gridpoints') not in ['unknown', 'unavailable'] }}";
        }
        {
          name = "NWS Precipitation Chance";
          default_entity_id = "sensor.nws_precipitation_chance";
          unit_of_measurement = "%";
          icon = "mdi:weather-rainy";
          state = ''
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {%- if periods -%}
              {{- periods[0].probabilityOfPrecipitation.value | default(0) -}}
            {%- else -%}
              unavailable
            {%- endif -%}
          '';
          availability = "{{ states('sensor.nws_hourly_forecast') not in ['unknown', 'unavailable'] and (state_attr('sensor.nws_hourly_forecast', 'periods') | default([]) | length > 0) }}";
        }
      ];
    }
    {
      binary_sensor =
        map
          (
            {
              id,
              friendlyName,
              event,
            }:
            {
              name = friendlyName;
              default_entity_id = "binary_sensor.${id}";
              device_class = "safety";
              # One sensor per NWS alert `event` string we care about --
              # https://api.weather.gov/alerts/active?point=... entries carry
              # exactly this name in properties.event.
              state = ''
                {{ state_attr('sensor.nws_active_alerts', 'features')
                   | default([])
                   | selectattr('properties.event', 'equalto', '${event}')
                   | list | count > 0 }}
              '';
              availability = "{{ states('sensor.nws_active_alerts') not in ['unknown', 'unavailable'] }}";
            }
          )
          [
            {
              id = "tornado_warning";
              friendlyName = "Tornado Warning";
              event = "Tornado Warning";
            }
            {
              id = "tornado_watch";
              friendlyName = "Tornado Watch";
              event = "Tornado Watch";
            }
            {
              id = "severe_thunderstorm_warning";
              friendlyName = "Severe Thunderstorm Warning";
              event = "Severe Thunderstorm Warning";
            }
            {
              id = "severe_thunderstorm_watch";
              friendlyName = "Severe Thunderstorm Watch";
              event = "Severe Thunderstorm Watch";
            }
          ];
    }
    {
      # Declarative weather entity sourced entirely from the "NWS
      # Forecast"/"NWS Hourly Forecast" rest sensors above, instead of
      # the UI-config-flow-only `met`/`nws` integrations (neither has
      # any Nix-expressible configuration).
      weather = [
        {
          name = "NWS";
          attribution = "Forecast data from the National Weather Service (api.weather.gov).";
          # Sourced from NWS's hourly period forecast feed (sensor.nws_hourly_forecast).
          # Every `{% %}` control tag below is `-`-trimmed on both sides, and
          # every final `{{ }}` output is too (`{{- ... -}}`) -- Jinja only
          # auto-strips whitespace *adjacent to `{% %}` tags* (HA's template
          # environment sets trim_blocks/lstrip_blocks), not around `{{ }}`
          # expressions or Nix's own indentation of the string below, so
          # without explicit trims here every value would come back with
          # stray leading/trailing whitespace -- harmless for the numeric
          # fields (Python's int()/float() ignore it) but breaks an exact
          # enum match like `condition`.
          condition = ''
            ${nwsConditionMap}
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {{- nws_condition(periods[0]) if periods else None -}}
          '';
          temperature = ''
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {{- periods[0].temperature if periods else None -}}
          '';
          apparent_temperature = ''
            ${nwsHeatIndexMacro}
            {{- nws_heat_index(0) -}}
          '';
          wind_speed = ''
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {%- set nums = (periods[0].windSpeed | regex_findall('[0-9]+') | map('int') | list) if periods else [] -%}
            {{- ((nums | sum) / (nums | length)) if nums | length > 0 else None -}}
          '';
          wind_bearing = ''
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {{- (periods[0].windDirection or None) if periods else None -}}
          '';
          humidity = ''
            {%- set periods = state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
            {{- periods[0].relativeHumidity.value if periods else None -}}
          '';
          # Pressure/visibility aren't in any of NWS's forecast feeds (only
          # its per-station observations, a different endpoint this doesn't
          # call), so the entity just omits those attributes.
          forecast_hourly = ''
            ${nwsConditionMap}
            ${nwsHeatIndexMacro}
            {%- set ns = namespace(forecast=[]) -%}
            {%- for period in state_attr('sensor.nws_hourly_forecast', 'periods') or [] -%}
              {%- set idx = loop.index0 -%}
              {%- set nums = period.windSpeed | regex_findall('[0-9]+') | map('int') | list -%}
              {%- set ns.forecast = ns.forecast + [{
                'datetime': period.startTime,
                'is_daytime': period.isDaytime,
                'condition': nws_condition(period),
                'temperature': period.temperature,
                'apparent_temperature': nws_heat_index(idx) | float(period.temperature),
                'precipitation_probability': period.probabilityOfPrecipitation.value | default(0),
                'humidity': period.relativeHumidity.value if period.relativeHumidity else None,
                'wind_speed': ((nums | sum) / (nums | length)) if nums | length > 0 else 0,
                'wind_bearing': period.windDirection or None,
              }] -%}
            {%- endfor -%}
            {{- ns.forecast -}}
          '';
          forecast_twice_daily = ''
            ${nwsConditionMap}
            {%- set ns = namespace(forecast=[]) -%}
            {%- for period in state_attr('sensor.nws_forecast', 'periods') or [] -%}
              {%- set nums = period.windSpeed | regex_findall('[0-9]+') | map('int') | list -%}
              {%- set ns.forecast = ns.forecast + [{
                'datetime': period.startTime,
                'is_daytime': period.isDaytime,
                'condition': nws_condition(period),
                'temperature': period.temperature,
                'precipitation_probability': period.probabilityOfPrecipitation.value | default(0),
                'wind_speed': ((nums | sum) / (nums | length)) if nums | length > 0 else 0,
                'wind_bearing': period.windDirection or None,
              }] -%}
            {%- endfor -%}
            {{- ns.forecast -}}
          '';
        }
      ];
    }
  ];
}
