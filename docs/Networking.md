# Networking

[← Back to root README](../README.md)

This document describes the main network paths and exposed ports for the FTPS file transfer service.

## Overview

The deployed service has two distinct traffic directions:

- inbound FTPS client traffic into Azure Container Apps
- outbound SFTP traffic from the FTPS container to one or more downstream targets

At a high level:

```text
External FTPS client
  -> HMCTS upstream firewall checks and NAT
  -> Azure Container Apps TCP ingress
  -> ProFTPD in the ftps-server container
  -> local upload directory
  -> lftp forwarding loop
  -> ACA vNET default route to HMCTS hub firewall
  -> HMCTS outbound firewall checks
  -> downstream SFTP target(s)
```

## Inbound FTPS

The FTPS runtime uses implicit FTPS.

- Control port: `990`
- Transport: TCP
- Default passive port range: `1024-1034`

These defaults are owned by Terraform through the `ftps` input object:

- `ftps.listen_port` defaults to `990`
- `ftps.passive_port_min` defaults to `1024`
- `ftps.passive_port_max` defaults to `1034`

The Container App is configured with external TCP ingress on the FTPS listen port, and Terraform also patches the Container App with `additionalPortMappings` so the passive FTPS ports are exposed as external TCP ports.

## Upstream firewall and NAT

Engineers should account for an Azure firewall sitting in front of the Azure Container App load balancer.

- Client connections first hit the firewall public IP
- The firewall NAT rules translate those public IP ports to the internal Azure ports exposed by the Container App ingress
- The firewall also provides an IP whitelist control to limit which client source addresses are allowed to connect

This firewall layer is not managed in this repository. It is controlled from the HMCTS `hub-terraform-infra` repository.

If inbound FTPS connectivity is being added, changed, or debugged, check both layers:

- this repository for the Container App ingress and passive FTPS port configuration
- `hub-terraform-infra` for the upstream firewall NAT and source IP whitelist rules

The ACA environment also sits in a spoke VNet whose default route sends `0.0.0.0/0` traffic to the HMCTS hub via a virtual appliance. In practice that means both directions are subject to central firewall handling:

- FTPS traffic entering the ACA estate is routed through the main HMCTS firewalls before it reaches the Container Apps load balancer
- SFTP traffic leaving the ACA VNet is also routed via the main HMCTS firewalls and can be subject to further checks there before reaching the downstream destination

For engineers, the important point is that inbound and outbound connectivity can both be blocked outside this repository even when the Container App, target host, and application configuration all look correct.

## Container Apps environment and health checks

The FTPS container runs inside an Azure Container Apps environment. In practice, engineers should think about three separate layers on the inbound path:

- the upstream Azure firewall public IP and NAT rules
- the Azure Container Apps environment ingress and load-balancing layer
- the FTPS container process itself

The Container Apps environment load-balances inbound TCP connections only to replicas that are considered ready.

This deployment configures explicit TCP health probes on the container:

- Readiness probe: TCP on port `8086`, every `10` seconds, after an initial `10` second delay
- Liveness probe: TCP on port `8086`, every `30` seconds, after an initial `15` second delay

Inside the container, `entrypoint.sh` starts a small listener on port `8086` specifically so Azure Container Apps can probe container health.

Operationally, that means:

- if the readiness probe is failing, the ACA environment should stop routing new FTPS traffic to that replica
- if the liveness probe keeps failing, ACA can restart the container
- a container can be running from a process perspective but still not be eligible for traffic until the readiness probe succeeds

When debugging connection issues, treat the health checks as part of the network path. A firewall rule, NAT mapping, or FTPS port setting can all look correct while the ACA environment still withholds traffic because the container is not passing readiness.

## Quick connectivity check

You can do a basic FTPS control-channel test with:

```bash
curl -v --ssl --insecure ftps://dtsft.demo.apps.hmcts.net
```

What this checks:

- DNS resolution for the FTPS endpoint
- reachability through the upstream HMCTS firewall and NAT path
- Azure Container Apps ingress reachability on the FTPS control port
- TLS negotiation on the implicit FTPS endpoint

What this does not check:

- passive FTPS data ports `1024-1034`
- successful authenticated login
- downstream SFTP forwarding

`--insecure` tells `curl` not to fail certificate validation. That makes the command useful as a first-hop network and TLS reachability test even when the client machine does not trust the presented certificate chain.

If this command cannot connect at all, focus first on DNS, firewall, NAT, ACA ingress, or replica readiness. If it connects but fails later, the next step is usually to test authenticated FTPS behaviour and then passive data-port reachability.

## Important limit

At the current defaults, the FTPS deployment needs these external TCP ports exposed through Azure Container Apps ingress:

- `990` for the implicit FTPS control connection
- `1024-1034` for passive FTPS data connections

That is a total of 12 exposed TCP ports.

At the time of writing, Azure Container Apps only allows 6 ingress ports by default. Because of that limit, the Terraform configuration alone is not enough to make the full FTPS passive range available.

After the Azure Container Apps environment is deployed, a Microsoft support request must be raised to allocate the additional ingress ports. Treat this as an operational dependency for any new environment or rebuild of the Container Apps environment.

This approval is not immediate. Plan for it as an overnight process rather than a same-session infrastructure change.

## Outbound SFTP

Uploaded files are forwarded out of the FTPS container over SFTP using `lftp`.

- Default SFTP port per target: `22`
- Remote directory default: `.`
- Multiple targets are supported through `ftps.forward_targets`

Each target can define:

- `host` or `host_secret_name`
- `port`
- `remote_dir`
- `username_secret_name`
- `password_secret_name`
- `key_vault_id`

When more than one target is configured, the runtime sends each uploaded file to each target in turn.

## Environment-specific behaviour

### Nonprod

Nonprod keeps a temporary downstream target in place until the real SFTP destination is available.

- Terraform creates a storage-account local user with SFTP enabled
- The generated hostname is `<storage-account>.blob.core.windows.net`
- Terraform writes the generated SFTP username and password into Key Vault
- That temporary target is used when explicit `ftps.forward_targets` values are not provided

### Prod

Prod does not create the temporary storage-account SFTP target automatically. Production forwarding targets and their secrets must be supplied explicitly.

## What changes when networking is updated

If you change FTPS networking behaviour, keep these areas aligned in the same change:

- Terraform inputs and Container App ingress configuration
- local runtime settings in `app/docker-compose.yaml`
- smoke coverage in `app/test-local-ftps.sh`
- operator documentation in this file and the root README


