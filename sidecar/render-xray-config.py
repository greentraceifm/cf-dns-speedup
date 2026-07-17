#!/usr/bin/env python3
"""Build a minimal Xray sidecar config without logging proxy credentials."""

from __future__ import annotations

import argparse
import copy
import ipaddress
import json
import os
from pathlib import Path
from typing import Any


PROXY_PROTOCOLS = {"vmess", "vless", "trojan", "shadowsocks", "socks", "http"}


def replace_server_address(outbound: dict[str, Any], candidate: str) -> int:
    settings = outbound.get("settings")
    if not isinstance(settings, dict):
        return 0

    replaced = 0
    if isinstance(settings.get("address"), str):
        settings["address"] = candidate
        replaced += 1

    for key in ("vnext", "servers"):
        servers = settings.get(key)
        if not isinstance(servers, list):
            continue
        for server in servers:
            if isinstance(server, dict) and isinstance(server.get("address"), str):
                server["address"] = candidate
                replaced += 1
    return replaced


def has_server_address(outbound: dict[str, Any]) -> bool:
    settings = outbound.get("settings")
    if not isinstance(settings, dict):
        return False
    if isinstance(settings.get("address"), str):
        return True
    return any(
        isinstance(server, dict) and isinstance(server.get("address"), str)
        for key in ("vnext", "servers")
        for server in (settings.get(key) if isinstance(settings.get(key), list) else [])
    )


def remove_router_sockopts(outbound: dict[str, Any]) -> None:
    stream = outbound.get("streamSettings")
    if not isinstance(stream, dict):
        return
    sockopt = stream.get("sockopt")
    if not isinstance(sockopt, dict):
        return
    sockopt.pop("mark", None)
    sockopt.pop("tproxy", None)
    if not sockopt:
        stream.pop("sockopt", None)


def build_config(
    source: dict[str, Any], candidate: str | None
) -> tuple[dict[str, Any], dict[str, Any]]:
    if candidate is not None:
        ipaddress.IPv4Address(candidate)
    outbounds = copy.deepcopy(source.get("outbounds"))
    if not isinstance(outbounds, list) or not outbounds:
        raise ValueError("source config has no outbounds")

    target: dict[str, Any] | None = None
    for index, outbound in enumerate(outbounds):
        if not isinstance(outbound, dict):
            continue
        protocol = str(outbound.get("protocol", "")).lower()
        if protocol not in PROXY_PROTOCOLS:
            continue
        candidate_outbound = copy.deepcopy(outbound)
        replaced = (
            replace_server_address(candidate_outbound, candidate)
            if candidate is not None
            else 0
        )
        if candidate is None:
            if not has_server_address(candidate_outbound):
                continue
        elif replaced == 0:
            continue
        remove_router_sockopts(candidate_outbound)
        outbounds[index] = candidate_outbound
        target = candidate_outbound
        break

    if target is None:
        raise ValueError("no supported proxy outbound with an address was found")

    target_tag = target.get("tag")
    if not isinstance(target_tag, str) or not target_tag:
        target_tag = "sidecar-proxy"
        target["tag"] = target_tag

    config: dict[str, Any] = {
        "log": {"loglevel": "warning"},
        "inbounds": [
            {
                "tag": "sidecar-socks",
                "listen": "127.0.0.1",
                "port": 1080,
                "protocol": "socks",
                "settings": {"auth": "noauth", "udp": False},
            }
        ],
        "outbounds": outbounds,
        "routing": {
            "domainStrategy": "AsIs",
            "rules": [
                {
                    "type": "field",
                    "inboundTag": ["sidecar-socks"],
                    "outboundTag": target_tag,
                }
            ],
        },
    }
    if isinstance(source.get("policy"), dict):
        config["policy"] = copy.deepcopy(source["policy"])

    stream = target.get("streamSettings") if isinstance(target, dict) else {}
    tls = stream.get("tlsSettings", {}) if isinstance(stream, dict) else {}
    summary = {
        "candidate": candidate,
        "target_mode": "candidate" if candidate is not None else "profile",
        "protocol": target.get("protocol"),
        "tag": target_tag,
        "network": stream.get("network") if isinstance(stream, dict) else None,
        "security": stream.get("security") if isinstance(stream, dict) else None,
        "server_name": tls.get("serverName") if isinstance(tls, dict) else None,
    }
    return config, summary


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", required=True)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--candidate")
    target.add_argument("--preserve-address", action="store_true")
    parser.add_argument("--output", required=True)
    parser.add_argument("--summary-output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    source_path = Path(args.source)
    output_path = Path(args.output)
    source = json.loads(source_path.read_text(encoding="utf-8"))
    config, summary = build_config(source, None if args.preserve_address else args.candidate)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(config, separators=(",", ":")), encoding="utf-8")
    os.chmod(output_path, 0o640)

    if args.summary_output:
        summary_path = Path(args.summary_output)
        summary_path.write_text(json.dumps(summary, sort_keys=True) + "\n", encoding="utf-8")
        os.chmod(summary_path, 0o644)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
