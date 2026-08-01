{ lib, ... }:
{
  # Home Assistant's own log never reaches the journal, so the alloy agent the
  # homelab logging module installs does not ship it and nothing downstream can
  # see a failed sign-in. Confirmed on this host rather than assumed: over two
  # days `journalctl -u home-assistant` held four lines, all of them systemd's
  # own "Starting"/"Started", and the journal carried no `hass` syslog
  # identifier at all -- only kernel, systemd and dbus. Everything the
  # application logs goes to /var/lib/hass/home-assistant.log instead.
  #
  # So the file is shipped directly. Alloy reads every *.alloy file under
  # /etc/alloy, which means this can be added beside the homelab module's
  # journal.alloy without modifying it, and the components share one namespace
  # so it forwards to that module's existing writer rather than declaring a
  # second connection to loki.
  environment.etc."alloy/home-assistant.alloy".text = ''
    // Managed by hosts/dubai. Ships home assistant's application log, which it
    // writes to a file rather than to the journal.

    local.file_match "home_assistant" {
      path_targets = [{
        __path__ = "/var/lib/hass/home-assistant.log",
        host     = "dubai",
        job      = "home-assistant",
      }]
    }

    loki.source.file "home_assistant" {
      targets    = local.file_match.home_assistant.targets
      forward_to = [loki.write.homelab.receiver]
    }
  '';

  # The state directory is 0700 hass:hass, so alloy cannot traverse it however
  # the file itself is permissioned. Widening it to group-readable and putting
  # alloy in the hass group is the narrowest change that lets the shipper read
  # one file: it grants the group nothing it could not already reach by being
  # hass, and no other user gains anything.
  #
  # Note this exposes the whole of /var/lib/hass to the hass group, which is
  # more than the log alone -- the secrets and the sqlite database live there
  # too. Alloy is the only member being added, and it only opens the path named
  # above, but it is a real widening rather than a free one.
  systemd.services.home-assistant.serviceConfig.StateDirectoryMode = lib.mkForce "0750";

  systemd.services.alloy.serviceConfig.SupplementaryGroups = [ "hass" ];
}
