from __future__ import annotations


def test_ftps_login_succeeds_with_credentials_fetched_from_key_vault(
    smoke_config,
    ftps_credentials: tuple[str, str],
    ftps_login_result: str,
) -> None:
    username, _ = ftps_credentials
    print(
        {
            "key_vault_name": smoke_config.key_vault_name,
            "username_secret_name": smoke_config.username_secret_name,
            "password_secret_name": smoke_config.password_secret_name,
            "username": username,
            "pwd": ftps_login_result,
        }
    )
    assert ftps_login_result


def test_ftps_returns_a_remote_directory_listing_after_successful_login(
    smoke_config,
    remote_entries: list[str],
) -> None:
    print(
        {
            "path": smoke_config.list_path,
            "entries": remote_entries,
        }
    )
    assert isinstance(remote_entries, list)