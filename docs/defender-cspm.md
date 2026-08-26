# Cloud Security Posture Management

Microsoft Defender for Cloud's free Foundational CSPM plan was run against the environment — a deliberate choice, not the paid Defender CSPM tier ($5/billable resource/month), consistent with this project's cost-conscious, always-free-tier-first approach throughout.

## Framing the Findings Accurately

27 findings were surfaced. Reporting that number at face value would misrepresent the environment: **7 of the 11 "High" severity items were Defender's own prompts to enable its paid plans** (Defender for Servers, SQL, Key Vault, Storage, Resource Manager, and CSPM itself) — not configuration gaps in this architecture, but upsell recommendations for a tier already deliberately declined. The accurate count: **4 genuine High-severity configuration findings**, alongside the 7 paid-tier prompts, plus a set of real Medium and Low findings below.

## Genuine High-Severity Findings

| Finding | Resource | Status |
|---|---|---|
| Disk encryption / EncryptionAtHost not enabled | `vm-web` | Documented, not remediated |
| No periodic missing-update check configured | `vm-web` | Documented, not remediated |
| No Azure AD administrator provisioned | SQL server | Documented, not remediated |
| No vulnerability assessment configured | SQL server | Documented, not remediated |

`vm-app` did not appear in the findings set at all at scan time — most likely explained by the VM having been recreated multiple times shortly before the scan (during Terraform troubleshooting), with Defender's assessment engine not yet caught up to the current instance, consistent with ingestion-lag patterns observed elsewhere in this project rather than a genuine zero-finding result.

## Remediated Findings

Two Medium findings were remediated directly in Terraform, mapped to the CIS Microsoft Azure Foundations Benchmark's Database Services and Storage domains (and the equivalent controls in the Microsoft Cloud Security Benchmark):

**SQL public network access disabled.** The SQL server already communicated exclusively through a Private Endpoint; the public network access option was a redundant, unused attack surface rather than an actively serving path. Fixed with `public_network_access_enabled = false` on `azurerm_mssql_server`.

**Storage account public blob access disallowed.** Fixed with `allow_nested_items_to_be_public = false` on `azurerm_storage_account`.

Both were verified two ways, not one: `terraform apply` reported the changes applied cleanly (`2 changed, 0 destroyed`), and Defender's own subsequent re-scan independently marked both findings **Completed** — two separate systems agreeing, not a single self-reported success taken at face value.

## A Finding Investigated and Deliberately Not Remediated

Defender also flagged the flow-log storage account for disallowing shared-key (access-key) authentication. This was investigated rather than applied blindly: Microsoft's own documentation confirms that Azure Network Watcher's flow log delivery mechanism specifically depends on storage account key-based access to write data — disabling it would have broken an already-working, previously-verified telemetry pipeline. This finding is documented as a deliberate, informed trade-off rather than remediated, consistent with this project's standard of investigating before changing a working control.

## Other Findings

Remaining Medium and Low findings (Key Vault firewall rules and deletion protection, Guest Configuration extension, VM host encryption, Azure Backup, Key Vault diagnostic logs, subscription security contact) were reviewed and left undeployed given the project's short remaining lifespan. Key Vault deletion protection specifically ties directly to this project's deliberate `purge_soft_delete_on_destroy = true` setting, needed for a clean `terraform destroy` — an intentional design trade-off, not an oversight. A VNet-level Azure Firewall recommendation was assessed as disproportionate in cost and scope for a lab environment and was not pursued.
