#!/usr/bin/env python3
import argparse
import csv
import ipaddress
import os
import tempfile
import time
from datetime import datetime
from decimal import Decimal, InvalidOperation
from pathlib import Path

SOURCE_FIELDS = [
    "observed_at", "candidate_ip", "direct_MBps", "round1_MBps", "round2_MBps",
    "min_MBps", "avg_MBps", "http1", "http2", "status", "profile_sha256", "path_mode",
]
EXPORT_FIELDS = [
    "schema_version", "exported_epoch", "observed_at", "candidate_ip", "direct_MBps",
    "round1_MBps", "round2_MBps", "min_MBps", "avg_MBps", "http1", "http2", "status",
    "path_mode", "candidate_tier",
]
SCHEMA_VERSION = "cfip-sidecar-candidates-v2"
HARD_OBSERVATION_MIN_MBPS = Decimal("3.5")
HARD_EXCELLENT_MIN_MBPS = Decimal("6.5")
MAX_EXPORT_ROWS = 3
MAX_SOURCE_BYTES = 1024 * 1024
MAX_SOURCE_ROWS = 100
CLOUDFLARE_V4 = tuple(ipaddress.ip_network(cidr) for cidr in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22",
    "141.101.64.0/18", "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20",
    "197.234.240.0/22", "198.41.128.0/17", "162.158.0.0/15", "104.16.0.0/13",
    "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
))

def parse_decimal(value: str, field: str) -> Decimal:
    try:
        number = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"invalid {field}: {value!r}") from exc
    if not number.is_finite() or number < 0:
        raise ValueError(f"invalid {field}: {value!r}")
    return number

def validate_row(row: dict[str, str], line_number: int) -> None:
    if None in row or any(value is None for value in row.values()):
        raise ValueError(f"line {line_number}: wrong field count")
    try:
        datetime.strptime(row["observed_at"], "%Y-%m-%d %H:%M:%S")
    except ValueError as exc:
        raise ValueError(f"line {line_number}: invalid observed_at") from exc
    address = ipaddress.ip_address(row["candidate_ip"])
    if address.version != 4 or not any(address in network for network in CLOUDFLARE_V4):
        raise ValueError(f"line {line_number}: candidate is outside Cloudflare IPv4 ranges")
    for field in ("direct_MBps", "round1_MBps", "round2_MBps", "min_MBps", "avg_MBps"):
        parse_decimal(row[field], field)
    if row["http1"] not in {"000", "200"} or row["http2"] not in {"000", "200"}:
        raise ValueError(f"line {line_number}: invalid HTTP status")
    if row["status"] not in {"low", "pass"}:
        raise ValueError(f"line {line_number}: invalid status")
    if row["path_mode"] != "sidecar_proxy":
        raise ValueError(f"line {line_number}: invalid path mode")


def exportable(row: dict[str, str], min_mbps: Decimal) -> bool:
    return (
        row["http1"] == "200"
        and row["http2"] == "200"
        and parse_decimal(row["min_MBps"], "min_MBps") >= min_mbps
    )


def export_candidates(
    source: Path,
    destination: Path,
    min_mbps: Decimal,
    excellent_min_mbps: Decimal,
    limit: int,
) -> int:
    if min_mbps < HARD_OBSERVATION_MIN_MBPS:
        raise ValueError(
            f"observation minimum cannot be below {HARD_OBSERVATION_MIN_MBPS} MB/s"
        )
    if excellent_min_mbps < HARD_EXCELLENT_MIN_MBPS:
        raise ValueError(
            f"excellent minimum cannot be below {HARD_EXCELLENT_MIN_MBPS} MB/s"
        )
    if excellent_min_mbps < min_mbps:
        raise ValueError("excellent minimum cannot be below observation minimum")
    if limit < 1 or limit > MAX_EXPORT_ROWS:
        raise ValueError(f"export limit must be between 1 and {MAX_EXPORT_ROWS}")
    if not source.is_file() or source.stat().st_size > MAX_SOURCE_BYTES:
        raise ValueError("source report is missing or too large")

    exported_epoch = str(int(time.time()))
    rows: list[dict[str, str]] = []
    with source.open("r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        if reader.fieldnames != SOURCE_FIELDS:
            raise ValueError("source report header does not match the observation contract")
        for index, row in enumerate(reader, start=2):
            if index - 1 > MAX_SOURCE_ROWS:
                raise ValueError("source report has too many rows")
            validate_row(row, index)
            if exportable(row, min_mbps):
                minimum = parse_decimal(row["min_MBps"], "min_MBps")
                rows.append(
                    {
                        "schema_version": SCHEMA_VERSION,
                        "exported_epoch": exported_epoch,
                        **{field: row[field] for field in EXPORT_FIELDS[2:-1]},
                        "status": (
                            "pass" if minimum >= excellent_min_mbps else "low"
                        ),
                        "candidate_tier": (
                            "excellent" if minimum >= excellent_min_mbps else "observation"
                        ),
                    }
                )

    rows.sort(
        key=lambda row: (
            -parse_decimal(row["min_MBps"], "min_MBps"),
            -parse_decimal(row["avg_MBps"], "avg_MBps"),
            ipaddress.ip_address(row["candidate_ip"]),
        )
    )
    rows = rows[:limit]

    destination.parent.mkdir(mode=0o755, parents=True, exist_ok=True)
    os.chmod(destination.parent, 0o755)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{destination.name}.", dir=destination.parent, text=True
    )
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(
                handle, fieldnames=EXPORT_FIELDS, delimiter="\t", lineterminator="\n"
            )
            writer.writeheader()
            writer.writerows(rows)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary_name, 0o644)
        os.replace(temporary_name, destination)
        if os.name != "nt":
            directory_fd = os.open(destination.parent, os.O_RDONLY)
            try:
                os.fsync(directory_fd)
            finally:
                os.close(directory_fd)
    except BaseException:
        try:
            os.unlink(temporary_name)
        except FileNotFoundError:
            pass
        raise
    return len(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description="Export sanitized, qualified CFIP Sidecar candidates")
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    parser.add_argument(
        "--min-mbps", default=str(HARD_OBSERVATION_MIN_MBPS), type=Decimal
    )
    parser.add_argument(
        "--excellent-min-mbps", default=str(HARD_EXCELLENT_MIN_MBPS), type=Decimal
    )
    parser.add_argument("--limit", default=MAX_EXPORT_ROWS, type=int)
    args = parser.parse_args()
    count = export_candidates(
        args.source,
        args.destination,
        args.min_mbps,
        args.excellent_min_mbps,
        args.limit,
    )
    print(f"exported_candidates={count}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
