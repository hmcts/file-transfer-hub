from __future__ import annotations


def test_ftps_public_fqdn_resolves_in_dns(
    smoke_config,
    resolved_addresses: list[str],
) -> None:
    print(f"{smoke_config.fqdn} resolved to: {', '.join(resolved_addresses)}")
    assert resolved_addresses


def test_ftps_is_reachable_on_control_port_990(tcp_probe_result: str) -> None:
    print(tcp_probe_result)
    assert tcp_probe_result.endswith("reachable")