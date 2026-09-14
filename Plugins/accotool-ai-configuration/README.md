# accotool-ai-configuration

Guided configuration workflow for accoTOOL FP&A writeback solutions in Power BI. Skills only - no bundled MCP server.

***NB! This plugin is work-in-progress***

## What this plugin does

Teaches Claude the accoTOOL writeback chain end to end - report page, accoTOOL visual (accoMASTERDATA / accoPLANNING), database, and semantic model - and which skill owns which layer, so a request lands with the right skill instead of being guessed at from one layer's vocabulary. Solution scope and shared entities are settled first (`accotool-ai-solution-planning`), which then hands off to the layer-specific skills below.

## Components

- **[`accotool-ai-solution-planning`](skills/accotool-ai-solution-planning/SKILL.md)** - establishes the scope of an accoTOOL solution: module inventory, shared entities, and page composition. Runs before every other skill below and hands off to them.
- **[`accotool-ai-customvisual-accomasterdata`](skills/accotool-ai-customvisual-accomasterdata/SKILL.md)** - configures accoMASTERDATA (AM), the row-per-key writeback visual, in PBIR/PBIP.
- **[`accotool-ai-customvisual-accoplanning`](skills/accotool-ai-customvisual-accoplanning/SKILL.md)** - configures accoPLANNING (AP), the period-matrix writeback visual, in PBIR/PBIP.
- **[`accotool-ai-sql-schema`](skills/accotool-ai-sql-schema/SKILL.md)** - builds/modifies the database backend (base, module, and datamart layers) that accoMASTERDATA, accoPLANNING, and accoCOMMENT write to. Expects a SQL execution path (e.g. `accotool-ai-sql-connect` below, or another MCP server if separately configured) to actually run its DDL.
- **[`accotool-ai-semantic-model`](skills/accotool-ai-semantic-model/SKILL.md)** - authors the Power BI semantic-model layer that governs the writeback data and relates it to the rest of the business model. Expects `powerbi-modeling-mcp`, if separately configured, for live model operations.
- **[`accotool-ai-sql-connect`](skills/accotool-ai-sql-connect/SKILL.md)** - signs in to an Azure SQL Database or Fabric SQL endpoint via Entra ID (device-code, MFA-capable) and executes T-SQL, using only Azure CLI + the `SqlServer` PowerShell module already on the machine. No MCP server, no config file - the zero-install fallback for ad-hoc SQL execution.

## Requirements

No MCP server is bundled or required by this plugin. `accotool-ai-sql-connect` needs PowerShell 7+, Azure CLI, and the `SqlServer` PowerShell module on the machine running it - see that skill's own Prerequisites section for exact install commands.

## Notes

- Each skill defers to the others for out-of-scope work rather than duplicating it - see each `SKILL.md`'s own description for the exact handoff points, or `accotool-ai-solution-planning`'s `references/accotool-ai-cross-layer-contracts.md` for the cross-layer picture.
- `accotool-ai-semantic-model` still names `powerbi-modeling-mcp` in its own metadata as the richer execution path when available - that server just isn't installed/declared by this plugin itself.

---

## Reference Documentation

### accotool-ai-solution-planning

The orchestrator skill. Establishes what an accoTOOL FP&A solution actually is — which modules it contains, how they interconnect, which entities are shared between them, and what each report page has to say — **before** any single layer starts building.

#### Why it exists

The other four accoTOOL skills each own one layer of the writeback chain and are deliberately scoped so none of them owns the whole. Without an orchestrator, a request like *"I want account planning by version"* gets answered as a visual-configuration question, and the decisions that should have been made once for the whole solution (is the version dimension shared? does it already exist? what does the page need to show alongside the grid?) get made accidentally, inside one module.

This skill runs first. It hands off once the frame is settled.

#### Status: in progress

The routing logic, the writeback-chain model, the check-the-database-first rule, the shared-entity conventions, and the page-composition step are all defined. The running record of actual modules and shared entities is still empty — it fills up as real solutions get built.

See [`SKILL.md`](accotool-ai-solution-planning/SKILL.md) for the agent-facing skill definition.

#### Three references, three jobs

| File | What it holds |
|---|---|
| [`accotool-ai-solution-architecture.md`](accotool-ai-solution-planning/references/accotool-ai-solution-architecture.md) | the running record of real modules, shared entities and page compositions — plus the solution-level open items (accoCOMMENT has no skill; nothing is verified in the Power BI Service; production credential hardening and RLS have no owner) |
| [`accotool-ai-cross-layer-contracts.md`](accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) | the invariants that exist **between** two layers and therefore belong to no single layer skill — nine of them — plus a symptom → owner router covering every documented failure mode in the set |
| [`accotool-ai-page-composition.md`](accotool-ai-solution-planning/references/accotool-ai-page-composition.md) | how an accoTOOL visual lives on a page beside the visuals that give it meaning: the answer/act/confirm structure, and where filter context stops being layout and becomes a write-path correctness concern |

The contracts file is the one the other four skills point back at. Each of them is correctly scoped to its own layer; the facts that span two layers had no owner until it existed, and they are where builds actually break.

#### The writeback chain this skill orchestrates

```
Report (application layer)  ← context visuals + accoTOOL input surface
   ↓ user types
accoTOOL visual             ← accotool-ai-customvisual-accomasterdata / -accoplanning
   ↓ writes back
Database / warehouse        ← accotool-ai-sql-schema  (stores, then applies business logic)
   ↓ prepared via views
Semantic model              ← accotool-ai-semantic-model  (governs, relates, defines)
   ↓ back onto the page
Report                      ← the same user sees the consequence of their own edit
```

A loop, not a pipeline.

#### Related skills

- `accotool-ai-customvisual-accomasterdata` — row-per-key writeback (dimensions, config tables, fact tables with one row per unique key combination).
- `accotool-ai-customvisual-accoplanning` — Row×Column period-matrix writeback (planning a measure across periods).
- `accotool-ai-sql-schema` — the database layer every module writes to; also owns the shared conventions this skill routes against (e.g. `accoTOOL$Base.Dim_Version#AM`).
- `accotool-ai-semantic-model` — the modeling layer that governs writeback data alongside the rest of the business model.
- Microsoft `powerbi-authoring` — generic report/visual authoring for the context visuals this skill specifies but does not build.

### accotool-ai-customvisual-accomasterdata

Configures the **accoMASTERDATA** (AM) proprietary Power BI custom visual — the writeback grid used for dimension/master-data editing (e.g. maintain an Employee table directly from a report).

#### Status: in progress

Placement, `rowIds`/`measures` data-role binding, editability defaults, field renaming without breaking writeback, connection/credential binding, the audit-log block, grid styling, shadow calculations, and dropdowns (including measure-bound dynamic lists) are all documented and verified against a real build. See [`references/accomasterdata.md`](accotool-ai-customvisual-accomasterdata/references/accomasterdata.md)'s own §12 for what isn't covered yet.

See [`SKILL.md`](accotool-ai-customvisual-accomasterdata/SKILL.md) for the agent-facing skill definition, and [`references/accomasterdata.md`](accotool-ai-customvisual-accomasterdata/references/accomasterdata.md) for the full technical documentation (confidence-marked findings, property tables, known gotchas).

#### Which of the two writeback visuals?

Shape decides, not vocabulary. **One row per business key** — a dimension, a config table, or a fact table where one row is one unique key combination (e.g. one row per project per budget version) — is accoMASTERDATA, however much the business calls it "planning". A **Row×Column period matrix**, planning a measure across periods with many editable cells per row, is accoPLANNING.

#### Related skills

- `accotool-ai-solution-planning` — the orchestrator; runs **before** this skill to settle module scope, shared entities, and what the report page has to say around the grid. It also owns the convention that a planning version/scenario is a shared `accoTOOL$Base.Dim_Version#AM` table maintained through this visual — not a per-module invention.
- `accotool-ai-customvisual-accoplanning` — the sibling skill for accoPLANNING (AP), the other accoTool writeback visual. Built independently; a handful of low-level Desktop/reload mechanics are shared between the two and noted in both files, but object groups, property names, and write semantics differ substantially — don't assume a fact from one applies to the other without checking.
- `accotool-ai-semantic-model` — owns the DAX/measure-authoring side of anything this skill binds to (e.g. the connection-bridge measures, or a dynamic-dropdown-feeding measure).
- `accotool-ai-sql-schema` — owns the database schema a given module writes to.

Across all five: `accotool-ai-solution-planning` also owns [`references/accotool-ai-cross-layer-contracts.md`](../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) — the invariants that span two layers, plus a symptom-to-owner router. Read it before wiring a module end to end, and whenever a failure surfaces somewhere other than where it was caused.

### accotool-ai-customvisual-accoplanning

Configures the **accoPLANNING** (AP) proprietary Power BI custom visual — the writeback grid used for budgeting/planning-style modules (e.g. plan an amount per account per period).

#### Status: in progress

Placement, the full `Row`/`Column`/`Measure`/`Transaction`/`NonWriteableMeasures`/`Comments` data-role set, the `Transaction`-role write-key resolution (including its critical measure-naming requirement), `planningConnection` credential binding, `batchRows` behaviour, per-cell comment binding, and shadow calculations (including the delta mechanism) are all documented and verified against a real build. See [`references/accoPLANNING.md`](accotool-ai-customvisual-accoplanning/references/accoPLANNING.md)'s own §9 for what isn't covered yet — dropdown cells, cell locking, splashing, min/max validation, and grid/layout styling among them.

See [`SKILL.md`](accotool-ai-customvisual-accoplanning/SKILL.md) for the agent-facing skill definition, and [`references/accoPLANNING.md`](accotool-ai-customvisual-accoplanning/references/accoPLANNING.md) for the full technical documentation (confidence-marked findings, property tables, known gotchas).

#### Which of the two writeback visuals?

Shape decides, not vocabulary. **Row×Column period matrix** — planning a measure across periods, many editable cells per row — is accoPLANNING. **One row per business key** — a dimension, a config table, or a fact table where one row is one unique key combination — is accoMASTERDATA, however much the business calls it "planning".

#### Related skills

- `accotool-ai-solution-planning` — the orchestrator; runs **before** this skill to settle module scope, shared entities, and what the report page has to say around the grid.
- `accotool-ai-customvisual-accomasterdata` — the sibling skill for accoMASTERDATA (AM), the other accoTool writeback visual. Built independently; a handful of low-level Desktop/reload mechanics are shared between the two and noted in both files, but object groups, property names, and write semantics differ substantially.
- `accotool-ai-semantic-model` — owns the DAX/measure-authoring side of anything this skill binds to (e.g. the connection-bridge measures, or a `Transaction`-role key-resolving measure).
- `accotool-ai-sql-schema` — owns the database schema a given module writes to.

Across all five: `accotool-ai-solution-planning` also owns [`references/accotool-ai-cross-layer-contracts.md`](../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) — the invariants that span two layers, plus a symptom-to-owner router. Read it before wiring a module end to end, and whenever a failure surfaces somewhere other than where it was caused.

### accotool-ai-sql-schema

Builds and modifies the accoTool database backend — the **logic layer** of the writeback chain. Stores what an accoTOOL visual writes back, then prepares it (joins, business logic, calculations) so the semantic model can govern it and the report can show it back to the user who typed it.

#### What it covers

Three schema layers, always in this order:

```
accoTOOL$Base          shared infrastructure — writeback identity, Config_Connection,
                       Config_Writeback, the single shared Log_Audit, Dim_Version#AM
accoTOOL$ModuleName    one per module — writeback tables, triggers, module views
dmAccoTOOL_Name        views only — the single contract everything downstream reads
```

Plus the three writeback patterns (dimension/accoMASTERDATA, fact/accoPLANNING with its optional RAW→Current merge, comment/accoCOMMENT), writeback identity provisioning, altering already-populated objects safely, seed data, and verification.

#### Status: mature

Confidence-marked throughout (🟢 confirmed against a real deployed database / 🟡 working baseline / ⚠️ open). §13 lists the standing design decisions most likely to get re-litigated by mistake — read it before "correcting" something that looks wrong (e.g. one shared writeback identity, not one per module).

#### Layout

- [`SKILL.md`](accotool-ai-sql-schema/SKILL.md) — scope, architecture, build order, mandatory pre-flight discovery, the confirm-before-ALTER safety rule, and §13's standing rules. This is what an agent loads whenever the skill triggers, so it deliberately stays small.
- [`references/accotool-ai-sql-schema-reference.md`](accotool-ai-sql-schema/references/accotool-ai-sql-schema-reference.md) — §3–§12: every DDL template, naming rule, and per-pattern build instruction. Read on demand, section by section, rather than loaded wholesale.

#### Related skills

- `accotool-ai-solution-planning` — runs **before** this skill. Owns the business discovery that §2.1 used to carry alone, the module inventory, and which entities are shared across modules.
- `accotool-ai-customvisual-accomasterdata` / `accotool-ai-customvisual-accoplanning` — configure the visuals that write into the tables this skill creates.
- `accotool-ai-semantic-model` — consumes the datamart views this skill produces; owns storage modes, relationships, and the DAX that bridges `Config_Connection` into visual-bound credentials.

Across all five: `accotool-ai-solution-planning` also owns [`references/accotool-ai-cross-layer-contracts.md`](../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) — the invariants that span two layers, plus a symptom-to-owner router. Read it before wiring a module end to end, and whenever a failure surfaces somewhere other than where it was caused.

### accotool-ai-semantic-model

Authors the Power BI semantic-model layer for accoTool writeback solutions — the **governance layer** of the writeback chain. Governs the data, relationships and definitions, and how writeback data interconnects with the rest of the business model.

#### What it covers

The project-specific facts a generic TMDL/semantic-model skill has no way to infer: loading datamart views as model tables, storage-mode assignment per view type (DirectQuery for writeback facts, Dual for dimensions, Import for config — and why an Import dimension must never relate to a DirectQuery fact), the inline `Sql.Database(...)` partition pattern, date-table sourcing against accoOneDB, the connection-measure bridge from `Config_Connection`/`Config_Writeback` into visual-bound credentials, the dedicated `_Measures` table and why any visual-bound measure must live there, naming constraints that are load-bearing for writeback, model-view layout via `diagramLayout.json`, and a set of hard-won environment gotchas.

#### Status: mature

Confidence-marked throughout (🟢 confirmed against a real deployed build / 🟡 working baseline / ⚠️ open). Generic modeling mechanics are deliberately **not** duplicated here — those defer to the Microsoft `semantic-model-authoring` plugin.

#### Layout

- [`SKILL.md`](accotool-ai-semantic-model/SKILL.md) — scope, ownership boundaries, the eight-step build order, and §11's environment gotchas. §11 stays here rather than moving to the reference because a missing gotcha there can cost a live model (`reload` can wipe it; a live push straight after a reload can crash Desktop).
- [`references/accotool-ai-semantic-model-reference.md`](accotool-ai-semantic-model/references/accotool-ai-semantic-model-reference.md) — §1–§10: the per-topic modeling detail, read on demand.

#### Related skills

- `accotool-ai-solution-planning` — runs **before** this skill; decides whether a module should exist and what its page has to say.
- `accotool-ai-sql-schema` — owns `Config_Connection`'s shape and produces the datamart views this layer loads.
- `accotool-ai-customvisual-accomasterdata` / `accotool-ai-customvisual-accoplanning` — own which literal visual property each measure binds to, and the exact string shape a property expects. The two visuals differ (`connection` vs. `planningConnection`, different property names) — never infer one from the other.

Across all five: `accotool-ai-solution-planning` also owns [`references/accotool-ai-cross-layer-contracts.md`](../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) — the invariants that span two layers, plus a symptom-to-owner router. Read it before wiring a module end to end, and whenever a failure surfaces somewhere other than where it was caused.

### accotool-ai-sql-connect

Signs in to an Azure SQL Database or Fabric SQL endpoint via Entra ID and executes a T-SQL statement, using only Azure CLI and the `SqlServer` PowerShell module already on the machine — no MCP server, no config file, no stored credential. The zero-install fallback for ad-hoc SQL execution when nothing richer is configured for the target.

#### Why it exists

A richer, purpose-built MCP server may already be configured for accoTOOL databases, but that needs installing and configuring per machine. This skill trades some of that convenience for zero setup: reuse the Azure CLI's own token cache (`az login --use-device-code`, MFA-capable) instead of a bespoke credential store. It does one thing — authenticate and execute — and nothing else: it does not know accoTOOL's schema conventions and does not decide whether a query is a good idea to run.

⚠️ Not necessarily a lighter-weight choice on every axis. Azure CLI (`az`) typically *does* need an elevated install once per machine — this skill's simplicity comes specifically from shelling out to `az`. Lighter on setup/config, not necessarily on admin rights — prefer an MCP server when it's already configured for the target; reach for this skill when it isn't, or for a target no MCP server knows about (e.g. a one-off Fabric endpoint).

#### Status: in progress

🟢 Confirmed end-to-end against a real Azure SQL Database — sign-in, query execution, and all three result paths (rows returned, empty result set, SQL error).

⚠️ Fabric SQL endpoints are not yet tested. The same token audience is expected to work (same underlying engine) but this is unconfirmed — treat Fabric support as aspirational until it's actually run once.

#### Layout

- [`SKILL.md`](accotool-ai-sql-connect/SKILL.md) — scope, the device-code auth protocol (never handle the user's credentials directly), prerequisites, and an `errorKind` → action table for the script's failure modes. This is what an agent loads whenever the skill triggers.
- [`scripts/connect-and-query.ps1`](accotool-ai-sql-connect/scripts/connect-and-query.ps1) — the actual implementation. Takes `-TenantId -Server -Database -Query` (or `-InputFile`), reuses the Azure CLI token cache so MFA only re-prompts when needed, and always emits one JSON object on stdout: `{ok, rowCount, rows, message}` on success, or `{ok:false, errorKind, message}` on failure.

#### Related skills

- `accotool-ai-sql-schema` — owns accoTOOL's actual database design (naming, schema layers, writeback patterns). This skill only runs the SQL that skill produces; it has no opinion on what the SQL should be.
- `accotool-ai-solution-planning` — the tenant/server/database a query targets should come from an established solution's architecture notes, not be guessed at.
