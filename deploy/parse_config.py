#!/usr/bin/env python3
"""Parse config.yml and output values for shell consumption.

Uses a minimal YAML subset parser (stdlib only) since PyYAML may not be installed.
Supports the specific config.yml structure used by Hermes deploy.

Usage:
    python3 parse_config.py config.yml mimir.enabled
    python3 parse_config.py config.yml mimir.port
    python3 parse_config.py config.yml users          # JSON array of user objects
    python3 parse_config.py config.yml scopes         # JSON array of scope objects
    python3 parse_config.py config.yml user.jimmy.name
    python3 parse_config.py config.yml user_ids       # Space-separated user IDs
"""

import json
import re
import sys


def parse_yaml(text):
    """Minimal YAML parser for the config.yml structure."""
    result = {"mimir": {}, "users": [], "scopes": []}
    current_section = None
    current_item = None

    for line in text.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        # Top-level keys
        if not line.startswith(" ") and not line.startswith("\t"):
            if stripped.startswith("mimir:"):
                current_section = "mimir"
                current_item = None
            elif stripped.startswith("users:"):
                current_section = "users"
                current_item = None
            elif stripped.startswith("scopes:"):
                current_section = "scopes"
                current_item = None
            continue

        # Mimir section
        if current_section == "mimir":
            m = re.match(r"\s+(\w+):\s*(.+)", line)
            if m:
                key, val = m.group(1), m.group(2).strip()
                if val.lower() == "true":
                    val = True
                elif val.lower() == "false":
                    val = False
                elif val.isdigit():
                    val = int(val)
                result["mimir"][key] = val

        # Users section
        elif current_section == "users":
            if stripped.startswith("- id:"):
                current_item = {"id": stripped.split(":", 1)[1].strip(), "scopes": []}
                result["users"].append(current_item)
            elif current_item is not None:
                if stripped.startswith("- ") and not stripped.startswith("- id:"):
                    current_item["scopes"].append(stripped[2:].strip())
                else:
                    m = re.match(r"\s+(\w+):\s*(.+)", line)
                    if m:
                        key, val = m.group(1), m.group(2).strip()
                        if val.lower() == "true":
                            val = True
                        elif val.lower() == "false":
                            val = False
                        current_item[key] = val

        # Scopes section
        elif current_section == "scopes":
            if stripped.startswith("- id:"):
                current_item = {"id": stripped.split(":", 1)[1].strip()}
                result["scopes"].append(current_item)
            elif current_item is not None:
                m = re.match(r"\s+(\w+):\s*(.+)", line)
                if m:
                    key, val = m.group(1), m.group(2).strip()
                    current_item[key] = val

    return result


def main():
    if len(sys.argv) < 3:
        print("Usage: parse_config.py <config.yml> <query>", file=sys.stderr)
        sys.exit(1)

    config_path = sys.argv[1]
    query = sys.argv[2]

    with open(config_path) as f:
        config = parse_yaml(f.read())

    if query == "mimir.enabled":
        print("true" if config["mimir"].get("enabled", False) else "false")
    elif query == "mimir.port":
        print(config["mimir"].get("port", 8100))
    elif query == "users":
        print(json.dumps(config["users"]))
    elif query == "scopes":
        print(json.dumps(config["scopes"]))
    elif query == "user_ids":
        print(" ".join(u["id"] for u in config["users"]))
    elif query.startswith("user."):
        parts = query.split(".")
        user_id, field = parts[1], parts[2]
        for u in config["users"]:
            if u["id"] == user_id:
                print(u.get(field, ""))
                break
    else:
        print(f"Unknown query: {query}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
