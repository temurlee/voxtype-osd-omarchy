#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
config_home="${XDG_CONFIG_HOME:-$HOME/.config}"
state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
package_dir="$config_home/voxtype/osd/voxtype-osd-omarchy"
config_file="$config_home/voxtype/config.toml"
state_file="$state_home/voxtype-osd-omarchy/install-state.json"

fail() {
    printf 'Error: %s\n' "$1" >&2
    exit 1
}

command -v voxtype >/dev/null || fail "Voxtype is required."
command -v python >/dev/null || fail "Python 3.11 or newer is required."
command -v voxtype-audio-bridge >/dev/null || fail "voxtype-audio-bridge is required."
if ! command -v quickshell >/dev/null && ! command -v qs >/dev/null; then
    fail "Quickshell is required."
fi

version="$(voxtype --version | awk '{print $2}')"
if [[ "$(printf '%s\n' 1.0.1 "$version" | sort -V | head -n1)" != "1.0.1" ]]; then
    fail "Voxtype 1.0.1 or newer is required; found $version."
fi

if command -v fc-match >/dev/null; then
    family="$(fc-match 'JetBrainsMono Nerd Font' --format '%{family}')"
    [[ "$family" == *"JetBrainsMono Nerd Font"* ]] || fail "JetBrainsMono Nerd Font is required."
fi

mkdir -p "$package_dir" "$(dirname -- "$config_file")" "$(dirname -- "$state_file")"
if [[ -f "$config_file" ]]; then
    cp "$config_file" "$config_file.bak.voxtype-osd-omarchy.$(date +%Y%m%d-%H%M%S)"
fi

install -m 0644 "$project_dir/VoiceOsd.qml" "$package_dir/VoiceOsd.qml"
install -m 0644 "$project_dir/voxtype-osd.toml" "$package_dir/voxtype-osd.toml"
install -m 0755 "$project_dir/uninstall.sh" "$package_dir/uninstall.sh"
mkdir -p "$package_dir/scripts"
install -m 0755 "$project_dir/scripts/osd_config.py" "$package_dir/scripts/osd_config.py"

python "$project_dir/scripts/osd_config.py" install \
    --config "$config_file" \
    --state "$state_file" \
    --package "$package_dir"

systemctl --user restart voxtype.service
sleep 2
systemctl --user is-active --quiet voxtype.service || fail "voxtype.service did not start."

style_file="${XDG_RUNTIME_DIR:?}/voxtype/quickshell-style.json"
python - "$style_file" "$package_dir/VoiceOsd.qml" <<'PY'
import json
from pathlib import Path
import sys

style = Path(sys.argv[1])
expected = sys.argv[2]
if not style.exists():
    raise SystemExit("Quickshell style state was not created.")
actual = json.loads(style.read_text()).get("custom_qml")
if actual != expected:
    raise SystemExit(f"Unexpected custom QML path: {actual!r}")
PY

printf '%s\n' \
    "voxtype-osd-omarchy installed successfully." \
    "Use your existing Voxtype shortcut to start dictation." \
    "Uninstall with: $package_dir/uninstall.sh"
