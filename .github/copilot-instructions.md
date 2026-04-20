# Copilot Instructions

- Treat `app/` as the FTPS image source of truth.
- Any change to the FTPS image runtime, startup, TLS handling, forwarding behavior, Dockerfile, or compose wiring must pass `app/test-local-ftps.sh` before the task is complete.
- Leave the local smoke environment clean when you are done. If you ran the test manually or interrupted it during debugging, bring `ftps-local-smoke` down before considering the task finished.
- Use `app/docker-compose.yaml` as the single local runtime for both manual FTPS-to-SFTP checks and the smoke test. Do not reintroduce a separate local test overlay unless there is a concrete need that cannot be handled in the base compose file.
- Keep the local compose stack disposable: the FTPS upload area and ProFTPD logs should remain on `tmpfs`, and the local SFTP sidecar should remain part of the default local stack.
- Keep `app/Makefile` aligned with the documented local workflows. When changing the local run or test flow, update the relevant `make` targets in the same change.
- Keep the manual local flow self-contained: `make up` should be able to bootstrap any minimal ignored local configuration it needs, while `app/test-local-ftps.sh` should remain deterministic and should not depend on user-specific local `.env` state.
- If an image change alters the local test workflow or runtime expectations, update `app/README.md` in the same change.
- Do not treat an image-only change as done based only on `docker build`; the FTPS startup and FTPS-to-SFTP forwarding smoke test must pass.