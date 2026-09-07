#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
package_dir="$config_home/voxtype/osd/voxtype-osd-omarchy"
config_file="$config_home/voxtype/config.toml"
state_file="$state_home/voxtype-osd-omarchy/install-state.json"

python "$script_dir/scripts/osd_config.py" uninstall \
    --config "$config_file" \
    --state "$state_file"

systemctl --user restart voxtype.service

if [[ "$script_dir" == "$package_dir" ]]; then
    cleanup="$package_dir"
    (sleep 1; rm -rf -- "$cleanup") >/dev/null 2>&1 &
else
    rm -rf -- "$package_dir"
fi
rm -f -- "$state_file"

printf '%s\n' "voxtype-osd-omarchy removed; the previous OSD settings were restored."
