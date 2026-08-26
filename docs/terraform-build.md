# Terraform Rebuild

The Phase 1 architecture — built manually via the Azure Portal and CLI — was rebuilt from scratch as version-controlled Terraform (`azurerm ~> 4.0`), reproducible from a clean subscription via `terraform apply`. This document covers the build itself and the real issues encountered along the way; for the detection and CI/CD layers built on top of it, see [`sentinel-detection.md`](./sentinel-detection.md) and [`cicd-pipeline.md`](./cicd-pipeline.md).

## Build Summary

~60 resources across network, security, identity, data, compute, load balancing, and monitoring layers, organized into purpose-scoped files (`network.tf`, `security.tf`, `keyvault.tf`, `sql.tf`, `compute.tf`, `loadbalancer.tf`, `monitoring.tf`) rather than one monolithic configuration.

- **Networking** — resource group, VNet, three subnets (web/app/data), matching the Phase 1 topology
- **Security** — three NSGs and three Application Security Groups, explicit allow rules scoped to ASG membership (not IP ranges) for tier-to-tier traffic, plus an explicit deny rule beneath Azure's default allow-VNet rule — segmentation that's actually enforced, not just assumed
- **Key Vault** — RBAC authorization, a private endpoint chain (private DNS zone, VNet link, endpoint), and a role assignment granting the deploying identity admin access
- **SQL** — server and database, private endpoint chain matching Key Vault's pattern, and a Terraform-generated admin password stored directly in Key Vault — `random_password`, never hardcoded, never typed by hand
- **Compute** — both VMs with NICs, ASG associations, and cloud-init bootstrap scripts (nginx on the web tier, Flask + a systemd service on the app tier); the app tier VM carries a system-assigned managed identity with a scoped Key Vault role assignment, closing the loop from server-side password generation to application-side retrieval
- **Load Balancer** — Standard SKU, public IP, backend pool, health probe, and routing rule — the sole public entry point, matching Phase 1's design principle exactly

## Verification

Resource creation succeeding is not the same as the architecture actually working. Two things were verified live, not assumed from a clean `terraform apply`:

- **The full identity chain** — VM managed identity → Key Vault secret retrieval → SQL authentication over a private endpoint — confirmed via a `/db-check` Flask endpoint returning `{"status": "connected"}`
- **The full public request path** — internet → Load Balancer → nginx → Flask — confirmed via a direct `curl` against the Load Balancer's public IP returning a healthy response

## Real Issues Encountered

Terraform's own validation (`terraform validate`) catches syntax and schema errors, but several real problems only surfaced against live Azure — the same distinction Phase 1 documented between "looks correct" and "empirically confirmed":

- **VM size string missing the `Standard_` prefix.** Referencing an Arm64-family SKU without the full `Standard_` prefix Azure requires (a shorthand carried over from earlier planning notes) produced a clear `InvalidParameter` error at `apply` time — not caught by `validate`, since the string was syntactically valid HCL, just semantically wrong for Azure's API.

- **VM `computer_name` rejecting characters `name` itself allowed.** Both VMs' underlying Linux hostname is derived from the resource `name` by default unless explicitly overridden — and hostname rules are stricter than Azure resource-naming rules, rejecting underscores that the resource `name` argument itself tolerated. Fixed by setting `computer_name` explicitly, decoupled from the ARM resource name.

- **A `pip install` failure specific to a live Ubuntu 24.04 image.** Flask's `blinker` dependency conflicted with a system-installed copy already present on the base image, installed via `apt` rather than `pip` — `pip` couldn't cleanly upgrade a package it didn't originally install. Fixed with `--ignore-installed` on the affected packages. Because the VM's bootstrap script runs under `set -e`, this single failure silently prevented every step after it (writing the app code, starting the service) from ever running — the VM appeared "created successfully" while the application inside it never started.

- **Load Balancer health probe rejecting the root path.** An HTTP probe configured against `/` failed because the Flask application has no route registered there — only `/health` and `/db-check` exist. Azure's probe correctly returned this as unhealthy (a 404, not a connection failure), which took real diagnostic work to trace back through nginx → Flask rather than assuming a network-layer problem.

- **Key Vault and Storage Account global naming constraints.** Both resource types require globally-unique names across all of Azure, not just this subscription — resolved with a `random_string` suffix pattern, with different constraints per resource type (Key Vault allows hyphens; Storage Accounts require lowercase alphanumeric only, no hyphens at all).

- **SSH public key path portability.** Initially referenced via `file()` pointing at an absolute local filesystem path — worked locally, but would have failed entirely once this same configuration needed to run on a GitHub Actions runner with no access to that path. Fixed by moving the key's actual content into a Terraform variable instead, which is also the more architecturally correct choice: a public key is meant to be shared, unlike the SQL password, which had a real reason to stay out of version control.

## Teardown

Full environment was deliberately destroyed via `terraform destroy` ahead of the Azure free-trial credit expiring, verified via `az group exists` returning `false` — not left to expire passively. One real finding surfaced during teardown: `terraform destroy` initially failed with `Error: ... the Resource Group still contains Resources`, pointing at two Network Watcher Traffic Analytics artifacts (a Data Collection Rule and Endpoint) that Azure itself silently provisions in the background the moment Traffic Analytics is enabled — never created by Terraform directly, so never tracked in state. Resolved by setting `prevent_deletion_if_contains_resources = false` on the provider's `resource_group` features block, which deletes the group via the Azure API directly rather than requiring every nested object to be Terraform-tracked first.
