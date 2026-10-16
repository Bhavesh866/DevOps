#!/usr/bin/env python3
import ipaddress
import json
import sys
from pathlib import Path

config_path = Path(
    sys.argv[1] if len(sys.argv) > 1
    else "infra/providers/aws/variables.example.tfvars"
)

# Parse the simple key/value example tfvars format used in this repository.
# This is intentionally not a general-purpose HCL parser.
values = {}
for raw_line in config_path.read_text().splitlines():
    line = raw_line.split("#", 1)[0].strip()
    if not line or "=" not in line:
        continue
    key, value = map(str.strip, line.split("=", 1))
    try:
        values[key] = json.loads(value)
    except json.JSONDecodeError:
        print(f"ERROR: Cannot parse {key} in {config_path}")
        sys.exit(1)

try:
    vpc = ipaddress.ip_network(values["vpc_cidr"], strict=True)
    public = [
        ipaddress.ip_network(cidr, strict=True)
        for cidr in values["public_subnet_cidrs"]
    ]
    private = [
        ipaddress.ip_network(cidr, strict=True)
        for cidr in values["private_subnet_cidrs"]
    ]
except (KeyError, ValueError) as exc:
    print(f"ERROR: Invalid or missing network input: {exc}")
    sys.exit(1)

if vpc.version != 4:
    print("ERROR: This assignment validator expects an IPv4 VPC CIDR.")
    sys.exit(1)

if len(public) < 2 or len(private) < 2:
    print("ERROR: At least two public and two private subnets are required.")
    sys.exit(1)

if len(public) != len(private):
    print("ERROR: Public and private subnet counts must match.")
    sys.exit(1)

all_subnets = [("public", n) for n in public] + [
    ("private", n) for n in private
]

for tier, subnet in all_subnets:
    if subnet.version != vpc.version or not subnet.subnet_of(vpc):
        print(f"ERROR: {tier} subnet {subnet} is not contained in VPC {vpc}.")
        sys.exit(1)

for i, (tier_a, subnet_a) in enumerate(all_subnets):
    for tier_b, subnet_b in all_subnets[i + 1:]:
        if subnet_a.overlaps(subnet_b):
            print(
                f"ERROR: Overlap detected: {tier_a} {subnet_a} and "
                f"{tier_b} {subnet_b}."
            )
            sys.exit(1)

print(
    f"Network input validation passed: VPC {vpc}, "
    f"{len(public)} public and {len(private)} private subnets."
)
