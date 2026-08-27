{ lib }:
let
  helpers = import ./lovelace/helpers.nix { };
  homeView = import ./lovelace/home.nix helpers;
  camerasView = import ./lovelace/cameras.nix helpers;
  petsView = import ./lovelace/pets.nix (helpers // { inherit lib; });
in
{
  # `lovelaceConfig` below only registers the Home view as an *extra*
  # sidebar dashboard (services.home-assistant.config.lovelace.dashboards.nixos-lovelace)
  # -- it does NOT replace HA's built-in default/primary dashboard, which
  # stays in storage mode and is what actually loads first. The built-in
  # primary dashboard's reserved url_path is "lovelace" -- defining a
  # `dashboards.lovelace` entry (as opposed to any other name) reconfigures
  # that primary dashboard itself rather than adding another sidebar
  # entry, making the Home view the initial page. (The legacy top-level
  # `lovelace.mode` does the same thing but is deprecated as of HA
  # 2026.8.) The module-generated `dashboards.nixos-lovelace` entry is
  # nulled out so it doesn't linger as a redundant second sidebar item.
  lovelace.dashboards = {
    nixos-lovelace = null;
    lovelace = {
      mode = "yaml";
      filename = "ui-lovelace.yaml";
      # `title` is required by the lovelace integration's config schema
      # even for the primary dashboard -- omitting it fails validation,
      # which cascades into `frontend` failing to load entirely and HA
      # falling into recovery mode.
      title = "Longleaf";
      icon = "mdi:view-dashboard";
    };
  };

  lovelaceConfig = {
    title = "Longleaf";
    views = [
      homeView
      camerasView
      petsView
    ];
  };
}
