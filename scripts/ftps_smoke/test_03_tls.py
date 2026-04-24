from __future__ import annotations

from datetime import timezone

from helpers import CertificateDetails


def test_ftps_responds_to_a_tls_handshake_on_port_990(
    smoke_config,
    certificate_details: CertificateDetails,
) -> None:
    print(
        f"TLS handshake succeeded against {smoke_config.fqdn}:{smoke_config.port} "
        f"with subject {certificate_details.subject}"
    )
    assert certificate_details.subject


def test_ftps_presents_a_certificate_on_port_990_that_matches_the_expected_public_hostname(
    smoke_config,
    certificate_details: CertificateDetails,
    certificate_hostname_matches: bool,
) -> None:
    print(
        {
            "hostname": smoke_config.fqdn,
            "subject": certificate_details.subject,
            "issuer": certificate_details.issuer,
            "san_dns_names": certificate_details.san_dns_names,
            "common_name": certificate_details.common_name,
        }
    )
    assert certificate_hostname_matches


def test_ftps_presents_a_certificate_on_port_990_that_is_within_its_validity_period(
    certificate_details: CertificateDetails,
    certificate_is_valid_for_window: bool,
) -> None:
    print(
        {
            "not_after": certificate_details.not_after.astimezone(timezone.utc).isoformat(),
        }
    )
    assert certificate_is_valid_for_window