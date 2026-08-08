{ homelab, ... }:
{
  # Node exporter (config/capabilities/misc/metrics.nix) so newyork's
  # Prometheus can scrape this host's hardware/OS metrics -- see
  # hosts/newyork/modules/services/prometheus.nix's "node" job.
  host.metrics.enable = true;
  networking.firewall.extraInputRules = homelab.lib.firewallAllowLocal 9100;
}
