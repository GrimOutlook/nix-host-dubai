{ homelab }:
{
  # WAN upload/download throughput, read straight from washington's
  # VictoriaMetrics (hosts/washington/modules/services/victoriametrics.nix)
  # rather than adding a second exporter path -- node_exporter on newyork scrapes
  # eth1 (the WAN NIC, see hosts/newyork/modules/default.nix's `iface`).
  # `rate(...)[5m]` (not 1m) because the scrape_interval is 1m; a 1m rate
  # window can span too few samples and intermittently return no data.
  sensor = map (
    { name, device }:
    {
      platform = "rest";
      inherit name;
      resource = "http://washington.${homelab.domains.local}:${toString homelab.hosts.washington.services.victoriametrics.ports.web.number}/api/v1/query";
      method = "GET";
      params.query = "rate(node_network_${device}_bytes_total{host=\"newyork\",device=\"eth1\"}[5m]) * 8 / 1000000";
      value_template = "{{ (value_json.data.result[0].value[1] | float(0)) | round(2) }}";
      unit_of_measurement = "Mbit/s";
      device_class = "data_rate";
      state_class = "measurement";
      scan_interval = 15;
    }
  ) [
    {
      name = "WAN Download Speed";
      device = "receive";
    }
    {
      name = "WAN Upload Speed";
      device = "transmit";
    }
  ];
}
