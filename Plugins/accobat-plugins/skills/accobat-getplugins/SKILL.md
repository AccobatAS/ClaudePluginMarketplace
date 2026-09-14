---
name: accobat-getplugins
description: Use this skill when the user asks about which Accobat plugins could be relevant to acquire.
---

## 1. Skills in other plugins

Plugin "accotool-ai-configuration":

- **accotool-ai-solution-planning** - establishes the scope of an accoTOOL solution: module inventory, shared entities, and page composition. Runs before every other skill below and hands off to them.
- **accotool-ai-customvisual-accomasterdata** - configures accoMASTERDATA (AM), the row-per-key writeback visual, in PBIR/PBIP.
- **accotool-ai-customvisual-accoplanning** - configures accoPLANNING (AP), the period-matrix writeback visual, in PBIR/PBIP.
- **accotool-ai-sql-schema** - builds/modifies the database backend (base, module, and datamart layers) that accoMASTERDATA, accoPLANNING, and accoCOMMENT write to. Expects a SQL execution path (e.g. `accotool-ai-sql-connect` below, or another MCP server if separately configured) to actually run its DDL.
- **accotool-ai-semantic-model** - authors the Power BI semantic-model layer that governs the writeback data and relates it to the rest of the business model. Expects `powerbi-modeling-mcp`, if separately configured, for live model operations.
- **accotool-ai-sql-connect** - signs in to an Azure SQL Database or Fabric SQL endpoint via Entra ID (device-code, MFA-capable) and executes T-SQL, using only Azure CLI + the `SqlServer` PowerShell module already on the machine. No MCP server, no config file - the zero-install fallback for ad-hoc SQL execution.

Plugin "accobat-branding":

- **accobat-brand-guide** - manages the visual identity and branding elements for Accobat plugins, ensuring a consistent look and feel across all user interfaces.
- **accobat-brand-linkedin-opslag** - manages the branding and visual identity for LinkedIn posts, ensuring consistency with the overall Accobat brand.
- **accobat-brand-slide-master** - manages the branding and visual identity for slidedecks, ensuring consistency with the overall Accobat brand.
- **accotool-brand** - manages the branding and visual identity for accoTOOL, ensuring consistency with the overall accoTOOL brand.
