from __future__ import annotations

from helpers import ContainerAppState


def test_ftps_container_app_state_is_available_after_deployment(
    container_app_state: ContainerAppState,
) -> None:
    print(
        "container app state:",
        {
            "name": container_app_state.name,
            "provisioning_state": container_app_state.provisioning_state,
            "running_status": container_app_state.running_status,
            "latest_ready_revision": container_app_state.latest_ready_revision,
        },
    )

    assert container_app_state.name
    assert container_app_state.provisioning_state == "Succeeded"
    assert container_app_state.running_status in {"Running", "unknown"}