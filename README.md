# Azure 3-Tier Secure Network Architecture

A self-directed cloud security project: designing, building, and validating a defense-in-depth 3-tier network architecture on Microsoft Azure — from scratch, with zero public IPs on any workload VM, managed-identity authentication, and full network segmentation.

## Overview

This project demonstrates hands-on cloud security engineering beyond coursework and certification study — applying real network segmentation, least-privilege identity, private connectivity, and monitoring practices to a fully built, fully validated architecture. Every security boundary was tested empirically, not assumed: real connectivity failures were diagnosed and resolved, real security gaps were identified and closed, and the resulting build reflects actual operational experience, not a tutorial walkthrough.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Tech Stack](#tech-stack)
- [Security Controls Implemented](#security-controls-implemented)
- [Validation Results](#validation-results)
- [Lessons Learned](#lessons-learned)
- [Reproducing This Build](#reproducing-this-build)
- [Cost Analysis](#cost-analysis)
- [What's Next](#whats-next)
- [About](#about)

## Architecture

```mermaid
graph TD
    Internet["Internet"] -->|"Public IP :80"| LB["Standard Load Balancer<br/>lb-3tier-dev"]
    LB -->|"Health-probed backend"| WebVM["vm-web-01 — nginx<br/>snet-web, no public IP"]
    WebVM -->|"Port 8080, ASG-scoped"| AppVM["vm-app-01 — Flask<br/>snet-app, no public IP<br/>System-Assigned Managed Identity"]
    AppVM -->|"Private Endpoint, port 443"| KV["Azure Key Vault<br/>RBAC, public access disabled"]
    AppVM -->|"Private Endpoint, port 1433"| SQL["Azure SQL Database<br/>Serverless, public access disabled"]

    style Internet fill:#f9f9f9,stroke:#333
    style LB fill:#cce5ff,stroke:#333
    style WebVM fill:#d4edda,stroke:#333
    style AppVM fill:#d4edda,stroke:#333
    style KV fill:#fff3cd,stroke:#333
    style SQL fill:#fff3cd,stroke:#333
```

**Design principle:** the Load Balancer is the only public IP in the entire architecture. Every other resource — both VMs, Key Vault, and SQL Database — has zero direct internet exposure. Each hop enforces its own network boundary via NSGs and Application Security Groups.

## Tech Stack

| Layer | Technology |
|---|---|
| Compute | Azure Virtual Machines (Ubuntu 22.04/24.04, Arm64, B-series burstable) |
| Web tier | nginx (reverse proxy) |
| Application tier | Python 3.12, Flask, pyodbc |
| Data tier | Azure SQL Database (serverless, always-free tier) |
| Secrets | Azure Key Vault (RBAC, Private Endpoint) |
| Identity | System-assigned Managed Identity, `DefaultAzureCredential` |
| Networking | VNet, NSGs, Application Security Groups, Private Endpoints, Private DNS Zones |
| Load balancing | Azure Standard Load Balancer |
| Monitoring | Azure Monitor, Log Analytics, Virtual Network Flow Logs, SQL Auditing |
| IaC / Tooling | Azure CLI, Azure Portal |

## Security Controls Implemented

- **Zero public IPs on workload VMs** — `vm-web-01` and `vm-app-01` are unreachable from the internet by design. The Load Balancer is the sole public entry point.
- **Network segmentation via NSGs and Application Security Groups** — each subnet (`snet-web`, `snet-app`, `snet-data`) enforces its own inbound rules, scoped to specific ASG membership rather than broad IP ranges. Web-to-app traffic is permitted only from `asg-web` on port 8080; all other inbound traffic is explicitly denied.
- **Managed identity authentication — no stored credentials** — `vm-app-01` authenticates to Key Vault using a system-assigned managed identity via `DefaultAzureCredential`. No password, connection string, or API key is stored in code, configuration, or environment variables.
- **Least-privilege identity scope** — only `vm-app-01` (the tier that requires database and secrets access) holds a managed identity. `vm-web-01` has no identity, no stored credentials, and no direct path to Key Vault or SQL. This holds by design even as the web tier's responsibilities grow: Layer 7 capabilities like a WAF, rate limiting, or TLS termination operate on request content, not backend credentials — so `vm-web-01` can absorb that additional security responsibility without ever needing authenticated access to the data layer.
- **Private connectivity for all PaaS services** — both Key Vault and Azure SQL Database are reachable only via Private Endpoint, with public network access explicitly disabled at the resource level. DNS resolution for both services routes through Private DNS Zones linked to the VNet, ensuring traffic never traverses the public internet even when the underlying resource resides in a different Azure region.
- **Layered access verification** — Key Vault and SQL Database access is controlled independently at multiple layers: RBAC role assignment (`Key Vault Secrets User`), network isolation (Private Endpoint), and — for SQL specifically — native database auditing, confirmed to log every connection attempt with source IP, host, and success/failure status.
- **Auto-shutdown and cost governance** — all compute resources are configured with scheduled auto-shutdown, and a subscription-level budget alert (with tightened thresholds) provides ongoing cost visibility throughout the build.

## Validation Results

Every security boundary in this architecture was tested empirically rather than assumed. The matrix below reflects actual test results from live validation sessions, including a real production-style incident encountered and resolved mid-testing.

### Connectivity Matrix

| # | Test | Expected | Actual | Result |
|---|---|---|---|---|
| 1 | Internet → Load Balancer → full request chain | 200 OK | 200 OK | ✅ Pass |
| 2 | Internet → `vm-web-01` direct (private IP) | Unreachable | `TcpTestSucceeded: False` | ✅ Pass |
| 3 | Internet → `vm-app-01` direct (private IP) | Unreachable | `TcpTestSucceeded: False` | ✅ Pass |
| 4a | Internet → SQL Server, raw TCP handshake | N/A | `TcpTestSucceeded: True` | ℹ️ Expected — Azure SQL's gateway layer accepts the initial handshake for all databases regardless of access configuration |
| 4b | Internet → SQL Server, actual authentication attempt | Rejected | Connection failed at login layer | ✅ Pass — confirms the real security boundary (`publicNetworkAccess: Disabled`) is enforced past the gateway |
| 5 | `vm-web-01` → `vm-app-01` on port 8080 (allowed path) | Success | Success (after incident resolution — see below) | ✅ Pass |
| 6 | Managed identity → Key Vault secret retrieval | Success | Confirmed via direct test script and production traffic | ✅ Pass |
| 7 | `vm-app-01` → Azure SQL via Private Endpoint | Success | Confirmed via `sqlcmd` and application traffic | ✅ Pass |

### Incident: ASG Membership Does Not Persist Across VM Restarts

During validation, a routine VM stop/start cycle caused the public-facing endpoint to fail. Root-cause analysis, conducted systematically rather than by guesswork:

1. Confirmed both VMs were running (ruled out power state)
2. Confirmed the Flask application was healthy via direct connection to `vm-app-01` (ruled out the application tier)
3. Ran a raw TCP connectivity test between `vm-web-01` and `vm-app-01` on port 8080 — confirmed genuinely blocked at the network layer
4. Identified that `vm-web-01`'s NIC had lost its Application Security Group membership — a previously undocumented finding: **ASG membership does not survive a VM deallocate/start cycle**, only initial assignment
5. Re-attached the ASG membership and verified via CLI (the Azure Portal has proven unreliable for confirming this specific setting throughout the build — CLI verification became a standing practice as a result)
6. Retested and confirmed full connectivity restored

This finding recurred in a later session, confirming it as a repeatable environment behavior rather than a one-time anomaly — it is now a standing operational check performed at the start of every session.

### Finding: Azure SQL Auditing Requires a Dedicated Configuration Path

Initial SQL audit logging was configured via the standard Azure Diagnostic Settings feature, pointed at the project's Log Analytics workspace. Despite showing as correctly configured, no audit data appeared even after generating confirmed real database traffic.

Root cause: Azure SQL Database auditing has its own dedicated configuration mechanism (`az sql db audit-policy`), separate from the generic Diagnostic Settings feature used for other resources in this project (e.g., VNet flow logs). The Diagnostic Settings entry only defined a data *destination* — it did not enable the SQL engine's native auditing feature, which is what actually generates the events. Attempting to configure both simultaneously produced a `Conflict` error, since each mechanism attempted to claim the same Log Analytics workspace as its target. Resolved by removing the generic diagnostic setting and configuring the audit policy directly with its own explicit Log Analytics target.

### Finding: Traffic Analytics Coverage Gap

Virtual Network flow logs reliably captured traffic crossing the VNet boundary to Azure public service endpoints (Key Vault, SQL via Private Link), with full attribution down to source VM, NIC, and subnet. However, intra-VNet traffic between subnets — specifically the web-to-app tier communication verified in Test #5 — did not appear in Traffic Analytics (`NTANetAnalytics`), despite the flow log being correctly scoped to the entire VNet and using Microsoft's documented query pattern for subnet-pair analysis.

This is a documented limitation observed in this environment, and it reinforces a practical lesson: **automated telemetry should not be the sole source of truth for validating security controls.** The ASG-related incident above was diagnosed and confirmed using direct connectivity testing precisely because Traffic Analytics did not surface it.

## Lessons Learned

Beyond the specific incidents documented above, this build surfaced several practical lessons in working with Azure at a level deeper than typical tutorial-following:

- **Region capacity is not the same as subscription quota.** A confirmed, non-zero quota for a VM size or service does not guarantee actual datacenter capacity is available at deployment time. This was encountered independently with both Azure SQL Database (blocked from deploying in the originally planned region despite no quota restriction) and VM sizing (an x64 B-series VM failed with `SkuNotAvailable` despite showing 0/4 quota used) — resolved by checking live SKU availability via `az vm list-skus` rather than relying on quota figures alone.

- **Not all portal-suggested defaults are the safest choice.** Deploying Azure Bastion through the portal's guided flow resulted in a Standard-tier deployment rather than the intended cost-free Developer SKU, generating unexpected charges before being identified and corrected via `az network bastion show --query "sku.name"`. This is now a standing verification step after any Bastion deployment.

- **Serverless compute has real cold-start behavior worth designing around.** Azure SQL Database's serverless auto-pause (used here for cost control) introduces a measurable delay on the first connection after a period of inactivity, occasionally exceeding a client's default connection timeout. This was resolved by extending connection timeout values and is a known, expected tradeoff of the serverless tier rather than a defect.

- **Azure-generated resource names don't always follow predictable conventions.** NIC and IP configuration names auto-generated by the platform (e.g., `vm-app-01VMNic`, `ipconfigvm-app-01`) did not match the hyphenated naming pattern assumed during planning. Verifying actual resource names via `az network nic list` before referencing them in later commands became a standard practice.

- **Resource providers require explicit registration on new subscriptions.** Early VM-related CLI commands returned empty results with no clear error, traced to the `Microsoft.Compute` resource provider not being registered on the subscription — resolved via `az provider register`. Confirming provider registration is now a first step on any new subscription.

- **Private Endpoints and Private DNS Zones are not part of Azure's free tier.** These carry a small ongoing hourly cost regardless of usage, distinct from the always-free and 12-months-free services used elsewhere in this build. Recognizing this early kept the project's cost trajectory predictable and well within the Azure free-trial credit.

## Reproducing This Build

This project was built manually via the Azure Portal and Azure CLI rather than Infrastructure as Code, in order to deliberately encounter and document the operational realities of working with Azure directly (see Lessons Learned above).

### Prerequisites
- An Azure subscription (this project was built and validated on Azure's free trial tier)
- Azure CLI installed and authenticated (`az login`)
- Basic familiarity with VNets, NSGs, and Linux VM administration

### High-Level Build Order
1. Resource Group and tagging strategy
2. Virtual Network with three subnets (web, app, data)
3. Network Security Groups and Application Security Groups
4. Azure Key Vault (RBAC, Private Endpoint, public access disabled)
5. Azure SQL Database (serverless, Private Endpoint, public access disabled)
6. Application tier VM — Flask app, systemd service, managed identity
7. Web tier VM — nginx reverse proxy
8. Standard Load Balancer — sole public entry point
9. Monitoring — Log Analytics, VNet flow logs, SQL auditing, alerting
10. Validation — full connectivity matrix testing

Detailed, phase-by-phase build notes are available in [`docs/`](./docs).

### Note on Cost
This build relies on Azure's always-free and 12-months-free service tiers for the majority of its footprint (VNet, NSGs, Bastion Developer SKU, 750 free VM hours/month, Azure SQL Database serverless free tier). Private Endpoints and Private DNS Zones carry a small ongoing hourly cost (not part of the free tier) — see [Lessons Learned](#lessons-learned) for details.

## Cost Analysis

| Resource | Tier | Cost |
|---|---|---|
| Virtual Network, Subnets, NSGs, ASGs | — | Always free |
| Virtual Machines (×2, B-series burstable) | Free trial allowance | Free (within 750 hrs/month, 12 months) |
| Azure SQL Database | Serverless, free-limit offer | Free (within monthly free-tier allowance) |
| Standard Load Balancer | Free trial allowance | Free (within 750 hrs/month, 12 months) |
| Key Vault | Standard | Free (within free-tier transaction allowance) |
| Private Endpoints (×2) | — | ~$0.01/hour each, not part of free tier |
| Private DNS Zones (×2) | — | Minor hosting cost, not part of free tier |
| Log Analytics Workspace | Pay-as-you-go | Free (within 5 GB/month ingestion allowance) |
| Storage Account (flow logs) | Standard, LRS | Minor, with 7-day lifecycle retention to control growth |

**Total cost incurred during development:** a small fraction of Azure's $200 free-trial credit, driven almost entirely by the two Private Endpoints running continuously and one transient Azure Bastion configuration error (identified and corrected — see Lessons Learned).

A subscription-level budget alert was configured from the outset of this project, at a threshold well below typical usage, specifically to surface any unexpected cost drift early rather than after the fact.

## What's Next

This project is actively maintained. Planned next steps include:

- **Infrastructure as Code** — rebuilding this architecture in Bicep or Terraform for repeatable, version-controlled deployment
- **Microsoft Defender for Cloud** — enabling the free CSPM (Cloud Security Posture Management) tier to generate security recommendations and a compliance score against this environment
- **Extended monitoring** — investigating and resolving the Traffic Analytics intra-VNet coverage gap documented above
- **Second web tier VM and Availability Set** — validating load distribution across multiple backend instances

Longer-term, lower-priority ideas under consideration: Microsoft Sentinel integration for detection engineering against this environment's telemetry, and Microsoft Purview for data governance — both would be scoped as short, deliberate, cost-monitored additions given their billing models differ from the always-free services used throughout this build.

## About

Built by Bryan Calderon — cybersecurity professional (TS/SCI, GIAC-certified, B.S. Applied Cybersecurity) with 24 years of USMC service, currently focused on cloud security engineering.

- **LinkedIn:** [linkedin.com/in/bryan-calderon-8bb31696](https://linkedin.com/in/bryan-calderon-8bb31696)
- **GitHub:** [github.com/bryancalderon1001-ctrl](https://github.com/bryancalderon1001-ctrl)
