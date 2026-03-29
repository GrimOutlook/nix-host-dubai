JUSTFILE_BASE_URL := \
  "https://raw.githubusercontent.com/GrimOutlook/nix-config/main/just"
JUST_EXT := "just"
JUST_DIR := ".just"

# It appears that variables in the import path is not supported
import? ".just/nix.just"
import? ".just/host.just"

# List recipes
default:
  just --list

# Fetch the all justfiles
[group('just')]
fetch-justfile: fetch-justfile-nix fetch-justfile-host

# Fetch the latest `host` justfile
[group('just')]
fetch-justfile-host:
  just _fetch-justfile "host"

# Fetch the latest `nix` justfile
[group('just')]
fetch-justfile-nix:
  just _fetch-justfile "nix"

# Fetch the latest justfile with the given name
[private]
_fetch-justfile config:
  #!/usr/bin/env bash
  set -euo pipefail
  [ `grep -E '^{{JUST_DIR}}/$' .gitignore` ] || echo "{{JUST_DIR}}/" >> .gitignore
  just_host_path="{{JUST_DIR}}/{{config}}.{{JUST_EXT}}"
  mkdir -p "$(dirname $just_host_path)"
  tmp_path="$(mktemp)"
  url="{{JUSTFILE_BASE_URL}}/{{config}}.{{JUST_EXT}}"
  if [ -f "$just_host_path" ]; then
    curl "$url" --output "$tmp_path"
    difft --exit-code "$just_host_path" "$tmp_path" && {
      echo '{{RED}}No changes to \`{{config}}\` justfile found{{NORMAL}}'
      exit 0
    }
  else
    curl "$url" --output "$tmp_path" || {
      echo "{{RED}}Failed to pull \`{{config}}.{{JUST_EXT}}\`{{NORMAL}}"
      exit 1
    }
  fi
  echo "{{GREEN}}Found new {{config}} justfile to use. Activating...{{NORMAL}}"
  mv "$tmp_path" "$just_host_path"
