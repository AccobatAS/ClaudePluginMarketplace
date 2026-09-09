---
name: accotool-ai-sql-connect
description: "Sign in to an Azure SQL Database or Fabric SQL endpoint via Entra ID (device-code flow, MFA-capable) and execute a T-SQL statement, using only Azure CLI and the SqlServer PowerShell module already on the machine - no MCP server, config file, or stored credential required. Use when: running ad-hoc T-SQL (SELECT/INSERT/UPDATE/DDL) against an Azure SQL Server or Fabric SQL endpoint with no MCP server configured for that target; verifying a tenant/server/database is reachable; diagnosing a firewall/network failure versus an auth failure. Triggers: a request naming a tenant ID plus a `*.database.windows.net`/Fabric SQL server and database with no existing MCP wiring; 'connect to this server and run this query'; 'sign in to Azure SQL'. Not for: a target already reachable through a configured MCP server - prefer that when it exists; this is the zero-install fallback."
metadata:
  author: Accobat A/S
  version: 0.1.0
---

# accoTool SQL Connect

**Scope:** getting from "tenant ID + server + database" to "a T-SQL statement ran and I can see the result" with nothing pre-installed beyond Azure CLI and the `SqlServer` PowerShell module - no MCP server, no `.mcp.json` entry, no stored secret. It does one thing: authenticate and execute. It does not know accoTOOL's schema conventions (`accotool-ai-sql-schema` owns that) and does not decide whether a query is a good idea to run.

**Why this exists:** a richer, purpose-built MCP server may already be configured for accoTOOL databases, but that needs installing/configuring per machine. This skill trades some of that convenience for zero setup: reuse the Azure CLI's own token cache instead of a bespoke credential store. Prefer an MCP server when it's already configured for the target; reach for this skill when it isn't, or when the target is something no MCP server knows about (e.g. a one-off Fabric endpoint).

⚠️ **This isn't a strictly better trade on every axis.** This skill's simplicity comes specifically from shelling out to `az`, which typically needs an elevated install once per machine (see Prerequisites below). Don't assume this skill is strictly lighter-weight than an MCP server alternative on every axis - it's lighter on setup/config, not necessarily on admin rights.

## Prerequisites (Windows)

| Requirement | Admin rights? | Notes |
|---|---|---|
| PowerShell 7.0+ | No (side-by-side with 5.1) | Script uses syntax 5.1 can't parse; checked explicitly at startup |
| Azure CLI (`az`) | **Usually yes** - MSI/winget install is machine-wide | The one real friction point for a locked-down machine; `pip install azure-cli` in a venv is a no-admin fallback, just slower |
| PowerShell module `SqlServer` | No (`-Scope CurrentUser`) | The script detects and reports this; doesn't self-install it (only genuinely no-admin, reversible module installs get auto-handled by the assisting agent, per this skill's own instructions below) |
| Network path to `login.microsoftonline.com` and the target `*.database.windows.net` | N/A | VPN/firewall allowlisting, as applicable to the target server |

The script checks all three tool prerequisites itself and returns a prescriptive `MissingTool` message (exact command, whether admin is needed, a no-admin fallback where one exists) rather than a bare "not found."

## How the auth works

Entra sign-in happens through `az login --use-device-code`, never through a password prompt this skill handles itself. **Never accept or type the user's password/MFA code on their behalf** - the whole point of the device-code flow is that the user completes sign-in in their own browser session; this skill only relays the code and URL Azure CLI prints.

Tokens are cached by Azure CLI (`~/.azure`), so sign-in is only needed once per tenant per token lifetime (observed: a cached session survives across multiple queries in the same working session without re-prompting). Don't force a fresh `az login` if `az account show` already reports the right tenant.

## Instructions

1. **Get the three required facts** if not already given: tenant ID, server (`<name>.database.windows.net` or a Fabric SQL endpoint hostname), database name. Don't guess a tenant ID - ask, or check `accotool-ai-solution-planning`'s architecture notes if this is an accoTOOL target.
2. **Run the bundled script**, [`scripts/connect-and-query.ps1`](scripts/connect-and-query.ps1), via the PowerShell tool:
   ```powershell
   ./scripts/connect-and-query.ps1 -TenantId <id> -Server <server> -Database <db> -Query "<sql>"
   ```
   It prints exactly one JSON object to stdout: `{ ok, rowCount, rows, message }` on success, or `{ ok:false, errorKind, message }` on failure. Parse that JSON rather than screen-scraping free text.
3. **If sign-in is required**, the script itself calls `az login --use-device-code` and that call blocks until the user completes it (or it times out). Run it as a background/monitored task so you can catch the device-code line (`To sign in, use a web browser to open the page ... and enter the code ...`) as soon as it's printed and relay the **URL and code only** to the user immediately - don't wait for the script to finish before telling them. Then wait for completion before reading the final JSON result.
4. **Branch on `errorKind` when `ok` is false:**
   | `errorKind` | Meaning | What to tell the user |
   |---|---|---|
   | `MissingTool` | Azure CLI or the `SqlServer` module isn't installed | Give the exact install command from the message - don't attempt to install `az` yourself (out of scope; module installs like `SqlServer`/`Az.Accounts` are fine to run with `-Scope CurrentUser`) |
   | `AuthFailed` | `az login` didn't complete, or the cached token expired | Re-run; a fresh device-code prompt will appear |
   | `FirewallBlocked` / `NetworkOrFirewall` | Server rejected the client IP, not the login | This is a server firewall rule, not a credentials problem - **never add a firewall rule yourself**; tell the user their client IP was rejected and point them at Azure Portal → SQL Server → Networking, or their own `az sql server firewall-rule create` |
   | `AuthRejected` | Entra login succeeded but SQL login failed for this identity | The signed-in user/service principal likely isn't provisioned as a database user - a database permissions problem, not a token problem |
   | `SqlError` | Query itself failed (syntax, permissions, missing object) | Ordinary SQL troubleshooting - the `message` field carries the server's own error text |
5. **Report `rowCount` and a preview of `rows`**, not the raw JSON blob, when relaying results back to the user - `rows` can be large.

## Known-working configuration (verified 2026-09-04)

🟢 **Azure SQL Database - confirmed end-to-end**, including the JSON-serialization and error-classification paths (success with rows, empty result set, SQL error), against a real Azure SQL Database, from this machine: PowerShell 7.4, Azure CLI 2.77, `SqlServer` module 22.4.5, ODBC Driver 17/18 both present. That server's firewall requires VPN or an allowlisted IP - a `FirewallBlocked` result there is expected off-VPN, not a bug in this skill.

⚠️ **Fabric SQL endpoints - not yet tested.** The `database.windows.net` token audience is expected to work for Fabric Warehouse/Lakehouse SQL analytics endpoints too (same underlying engine), but this has not been confirmed against a real Fabric endpoint. Treat Fabric support as unverified until it's actually run once - don't assume it works just because the description mentions it.

`Az.Accounts` / `Connect-AzAccount` turned out to be unnecessary - Azure CLI's own token (`az account get-access-token`) fed directly into `Invoke-Sqlcmd -AccessToken` is sufficient and is what the script uses. Don't add `Az.Accounts` as a dependency without a reason.

## Out of scope - hand off, don't improvise

- accoTOOL naming/schema conventions, what table a value belongs in → `accotool-ai-sql-schema`
- Whether an entity should exist at all / solution scope → `accotool-ai-solution-planning`
- Anything the target's own MCP server already handles, if one is configured for it
