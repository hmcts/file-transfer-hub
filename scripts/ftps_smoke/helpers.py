from __future__ import annotations

import json
import os
import socket
import ssl
import subprocess
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from ftplib import FTP_TLS, all_errors
from typing import Any

from cryptography import x509
from cryptography.x509.oid import ExtensionOID, NameOID


DEFAULT_PORT = 990
DEFAULT_LIST_PATH = "upload/"
DEFAULT_CERT_VALIDITY_WINDOW_SECONDS = 0


class SmokeCheckError(RuntimeError):
    pass


@dataclass(frozen=True)
class SmokeConfig:
    fqdn: str
    container_app_id: str
    key_vault_name: str
    port: int = DEFAULT_PORT
    username_secret_name: str = "ftps-local-username"
    password_secret_name: str = "ftps-local-password"
    list_path: str = DEFAULT_LIST_PATH
    cert_validity_window_seconds: int = DEFAULT_CERT_VALIDITY_WINDOW_SECONDS


@dataclass(frozen=True)
class ContainerAppState:
    name: str
    provisioning_state: str
    running_status: str
    latest_ready_revision: str


@dataclass(frozen=True)
class CertificateDetails:
    subject: str
    issuer: str
    not_after: datetime
    san_dns_names: tuple[str, ...]
    common_name: str | None


class ImplicitFTP_TLS(FTP_TLS):
    def connect(self, host: str = "", port: int = 0, timeout: float = -999, source_address=None):
        welcome = super().connect(host, port, timeout, source_address)
        self.sock = self.context.wrap_socket(self.sock, server_hostname=self.host)
        self.file = self.sock.makefile("r", encoding=self.encoding)
        return welcome


def env(name: str, default: str | None = None) -> str:
    value = os.environ.get(name, default)
    if value is None or value == "":
        raise SmokeCheckError(f"Missing required environment variable: {name}")
    return value


def build_config() -> SmokeConfig:
    return SmokeConfig(
        fqdn=env("FTPS_SMOKE_FQDN"),
        container_app_id=env("FTPS_SMOKE_CONTAINER_APP_ID"),
        key_vault_name=env("FTPS_SMOKE_KEY_VAULT_NAME"),
        port=int(os.environ.get("FTPS_SMOKE_PORT", str(DEFAULT_PORT))),
        username_secret_name=os.environ.get("FTPS_SMOKE_USERNAME_SECRET_NAME", "ftps-local-username"),
        password_secret_name=os.environ.get("FTPS_SMOKE_PASSWORD_SECRET_NAME", "ftps-local-password"),
        list_path=os.environ.get("FTPS_SMOKE_LIST_PATH", DEFAULT_LIST_PATH),
        cert_validity_window_seconds=int(
            os.environ.get(
                "FTPS_SMOKE_CERT_VALIDITY_WINDOW_SECONDS",
                str(DEFAULT_CERT_VALIDITY_WINDOW_SECONDS),
            )
        ),
    )


def run_command(command: list[str]) -> str:
    completed = subprocess.run(command, check=False, capture_output=True, text=True)
    if completed.returncode != 0:
        stderr = completed.stderr.strip()
        stdout = completed.stdout.strip()
        detail = stderr or stdout or f"command failed with exit code {completed.returncode}"
        raise SmokeCheckError(detail)
    return completed.stdout.strip()


def run_az(*args: str) -> str:
    return run_command(["az", *args])


def fetch_container_app_state(config: SmokeConfig) -> ContainerAppState:
    resource_name = run_az("resource", "show", "--ids", config.container_app_id, "--query", "name", "-o", "tsv")
    raw_state = run_az("containerapp", "show", "--ids", config.container_app_id, "-o", "json")
    payload: dict[str, Any] = json.loads(raw_state)
    properties = payload.get("properties", {})

    return ContainerAppState(
        name=resource_name,
        provisioning_state=properties.get("provisioningState", "unknown"),
        running_status=properties.get("runningStatus", "unknown"),
        latest_ready_revision=properties.get("latestReadyRevisionName", "unknown"),
    )


def resolve_dns(config: SmokeConfig) -> list[str]:
    addresses = {item[4][0] for item in socket.getaddrinfo(config.fqdn, None, type=socket.SOCK_STREAM)}
    if not addresses:
        raise SmokeCheckError(f"{config.fqdn} did not resolve")
    return sorted(addresses)


def probe_tcp(config: SmokeConfig) -> str:
    with socket.create_connection((config.fqdn, config.port), timeout=5):
        return f"{config.fqdn}:{config.port} reachable"


def fetch_certificate(config: SmokeConfig) -> CertificateDetails:
    context = ssl.create_default_context()
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE

    with socket.create_connection((config.fqdn, config.port), timeout=5) as raw_socket:
        with context.wrap_socket(raw_socket, server_hostname=config.fqdn) as wrapped_socket:
            certificate_bytes = wrapped_socket.getpeercert(binary_form=True)

    if not certificate_bytes:
        raise SmokeCheckError(f"No certificate was returned by {config.fqdn}:{config.port}")

    certificate = x509.load_der_x509_certificate(certificate_bytes)

    try:
        san_extension = certificate.extensions.get_extension_for_oid(ExtensionOID.SUBJECT_ALTERNATIVE_NAME)
        san_dns_names = tuple(san_extension.value.get_values_for_type(x509.DNSName))
    except x509.ExtensionNotFound:
        san_dns_names = ()

    common_names = certificate.subject.get_attributes_for_oid(NameOID.COMMON_NAME)
    common_name = common_names[0].value if common_names else None

    not_after = getattr(certificate, "not_valid_after_utc", None)
    if not_after is None:
        not_after = certificate.not_valid_after.replace(tzinfo=timezone.utc)

    return CertificateDetails(
        subject=certificate.subject.rfc4514_string(),
        issuer=certificate.issuer.rfc4514_string(),
        not_after=not_after,
        san_dns_names=san_dns_names,
        common_name=common_name,
    )


def certificate_matches_hostname(details: CertificateDetails, hostname: str) -> bool:
    candidate_names = list(details.san_dns_names)
    if not candidate_names and details.common_name:
        candidate_names.append(details.common_name)

    for candidate in candidate_names:
        if hostname_matches(candidate, hostname):
            return True

    return False


def hostname_matches(pattern: str, hostname: str) -> bool:
    if pattern == hostname:
        return True
    if not pattern.startswith("*."):
        return False

    suffix = pattern[1:]
    return hostname.endswith(suffix) and hostname.count(".") == pattern.count(".")


def certificate_is_current(details: CertificateDetails, validity_window_seconds: int) -> bool:
    return details.not_after > datetime.now(timezone.utc) + timedelta(seconds=validity_window_seconds)


def fetch_secret(config: SmokeConfig, secret_name: str) -> str:
    return run_az(
        "keyvault",
        "secret",
        "show",
        "--vault-name",
        config.key_vault_name,
        "--name",
        secret_name,
        "--query",
        "value",
        "-o",
        "tsv",
    )


def fetch_credentials(config: SmokeConfig) -> tuple[str, str]:
    return (
        fetch_secret(config, config.username_secret_name),
        fetch_secret(config, config.password_secret_name),
    )


def connect_ftps(config: SmokeConfig, username: str, password: str) -> ImplicitFTP_TLS:
    client = ImplicitFTP_TLS(timeout=10)
    client.context.check_hostname = False
    client.context.verify_mode = ssl.CERT_NONE

    try:
        client.connect(config.fqdn, config.port)
        client.login(username, password)
        client.prot_p()
        return client
    except all_errors as error:
        try:
            client.close()
        except Exception:
            pass
        raise SmokeCheckError(str(error)) from error


def verify_ftps_login(config: SmokeConfig, username: str, password: str) -> str:
    client = connect_ftps(config, username, password)
    try:
        return client.pwd()
    finally:
        safe_quit(client)


def list_remote_directory(config: SmokeConfig, username: str, password: str) -> list[str]:
    client = connect_ftps(config, username, password)
    normalized_path = config.list_path.rstrip("/") or "/"

    try:
        if normalized_path != "/":
            client.cwd(normalized_path)
        return client.nlst()
    except all_errors as error:
        raise SmokeCheckError(str(error)) from error
    finally:
        safe_quit(client)


def safe_quit(client: FTP_TLS) -> None:
    try:
        client.quit()
    except Exception:
        try:
            client.close()
        except Exception:
            pass