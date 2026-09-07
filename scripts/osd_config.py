#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import re
import tempfile
import tomllib

KEYS = ("frontend", "layout", "plugin_path")


def read_config(path: Path) -> tuple[str, dict]:
    if not path.exists():
        return "", {}
    text = path.read_text()
    return text, tomllib.loads(text)


def replace_osd_values(text: str, values: dict[str, str | None]) -> str:
    lines = text.splitlines(keepends=True)
    start = next((i for i, line in enumerate(lines) if line.strip() == "[osd]"), None)

    if start is None:
        if not any(value is not None for value in values.values()):
            return text
        if text and not text.endswith("\n"):
            text += "\n"
        block = ["\n[osd]\n"]
        block.extend(f'{key} = {json.dumps(value)}\n' for key, value in values.items() if value is not None)
        return text + "".join(block)

    end = len(lines)
    for i in range(start + 1, len(lines)):
        stripped = lines[i].strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            end = i
            break

    key_pattern = re.compile(r"^\s*(frontend|layout|plugin_path)\s*=")
    body = [line for line in lines[start + 1:end] if not key_pattern.match(line)]
    while body and not body[-1].strip():
        body.pop()
    body.extend(f'{key} = {json.dumps(value)}\n' for key, value in values.items() if value is not None)
    if end < len(lines):
        body.append("\n")
    return "".join(lines[:start + 1] + body + lines[end:])


def atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = path.stat().st_mode & 0o777 if path.exists() else 0o600
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temp_path = Path(handle.name)
    temp_path.chmod(mode)
    os.replace(temp_path, path)


def install(config: Path, state: Path, package: Path) -> None:
    text, parsed = read_config(config)
    if not state.exists():
        osd = parsed.get("osd", {})
        state.parent.mkdir(parents=True, exist_ok=True)
        state.write_text(json.dumps({
            "previous": {
                key: {"present": key in osd, "value": osd.get(key)}
                for key in KEYS
            }
        }, indent=2) + "\n")

    updated = replace_osd_values(text, {
        "frontend": "quickshell",
        "layout": "custom",
        "plugin_path": str(package),
    })
    tomllib.loads(updated)
    atomic_write(config, updated)


def uninstall(config: Path, state: Path) -> None:
    if not state.exists():
        raise SystemExit(f"Install state not found: {state}")
    text, _ = read_config(config)
    saved = json.loads(state.read_text())["previous"]
    values = {
        key: saved[key]["value"] if saved[key]["present"] else None
        for key in KEYS
    }
    updated = replace_osd_values(text, values)
    tomllib.loads(updated)
    atomic_write(config, updated)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("install", "uninstall"))
    parser.add_argument("--config", required=True, type=Path)
    parser.add_argument("--state", required=True, type=Path)
    parser.add_argument("--package", type=Path)
    args = parser.parse_args()

    if args.action == "install":
        if args.package is None:
            parser.error("--package is required for install")
        install(args.config, args.state, args.package)
    else:
        uninstall(args.config, args.state)


if __name__ == "__main__":
    main()
