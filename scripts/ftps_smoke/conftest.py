from __future__ import annotations

import shutil

import pytest

from helpers import (
    CertificateDetails,
    ContainerAppState,
    SmokeConfig,
    build_config,
    certificate_is_current,
    certificate_matches_hostname,
    fetch_certificate,
    fetch_container_app_state,
    fetch_credentials,
    list_remote_directory,
    probe_tcp,
    resolve_dns,
    run_az,
    verify_ftps_login,
)


@pytest.fixture(scope="session")
def smoke_config() -> SmokeConfig:
    return build_config()


@pytest.fixture(scope="session", autouse=True)
def ensure_required_tools() -> None:
    required_tools = ("az", "python3")
    missing_tools = [tool for tool in required_tools if shutil.which(tool) is None]
    if missing_tools:
        pytest.fail(f"Missing required tools: {', '.join(missing_tools)}")

    run_az("config", "set", "extension.use_dynamic_install=yes_without_prompt")


@pytest.fixture(scope="session")
def container_app_state(smoke_config: SmokeConfig) -> ContainerAppState:
    return fetch_container_app_state(smoke_config)


@pytest.fixture(scope="session")
def resolved_addresses(smoke_config: SmokeConfig) -> list[str]:
    return resolve_dns(smoke_config)


@pytest.fixture(scope="session")
def tcp_probe_result(smoke_config: SmokeConfig, resolved_addresses: list[str]) -> str:
    return probe_tcp(smoke_config)


@pytest.fixture(scope="session")
def certificate_details(smoke_config: SmokeConfig, tcp_probe_result: str) -> CertificateDetails:
    return fetch_certificate(smoke_config)


@pytest.fixture(scope="session")
def ftps_credentials(smoke_config: SmokeConfig, certificate_details: CertificateDetails) -> tuple[str, str]:
    return fetch_credentials(smoke_config)


@pytest.fixture(scope="session")
def ftps_login_result(
    smoke_config: SmokeConfig,
    ftps_credentials: tuple[str, str],
) -> str:
    username, password = ftps_credentials
    return verify_ftps_login(smoke_config, username, password)


@pytest.fixture(scope="session")
def remote_entries(
    smoke_config: SmokeConfig,
    ftps_credentials: tuple[str, str],
    ftps_login_result: str,
) -> list[str]:
    username, password = ftps_credentials
    return list_remote_directory(smoke_config, username, password)


@pytest.fixture(scope="session")
def certificate_hostname_matches(
    smoke_config: SmokeConfig,
    certificate_details: CertificateDetails,
) -> bool:
    return certificate_matches_hostname(certificate_details, smoke_config.fqdn)


@pytest.fixture(scope="session")
def certificate_is_valid_for_window(
    smoke_config: SmokeConfig,
    certificate_details: CertificateDetails,
) -> bool:
    return certificate_is_current(certificate_details, smoke_config.cert_validity_window_seconds)