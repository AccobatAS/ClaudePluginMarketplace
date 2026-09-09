---
name: accotool-ai-sql-schema
description: "Build or modify the accoTool database backend — base, module, and datamart layers — for accoPLANNING, accoMASTERDATA, and accoCOMMENT writeback. The logic layer of the accoTOOL writeback chain: it stores what a visual writes back and prepares it, via views, for the semantic model to govern and the report to read. Use when: creating a new planning module, designing dimension/fact tables, provisioning the shared writeback identity, or working with Config_Connection/Config_Writeback/Log_Audit. Does not cover semantic model authoring, Power BI report/PBIR authoring, TMDL, or visual formatting configuration — defer to accotool-ai-customvisual-accomasterdata or accotool-ai-customvisual-accoplanning for a visual's own configuration, accotool-ai-semantic-model for the modeling layer, accotool-ai-solution-planning for solution scope, and the Microsoft powerbi-authoring / semantic-model-authoring plugins for generic mechanics."
metadata:
  author: Accobat A/S
  version: 2.4.0
---
# accoTool SQL & Schema Build

**Scope:** Database/schema layer only — pre-flight discovery, naming, base objects, module objects, datamart views, writeback identity provisioning, seed data. Deliberately self-contained: nothing here depends on, or should reference, Power BI file mechanics, TMDL, semantic-model storage modes, DAX, or accoPLANNING/accoMASTERDATA/accoCOMMENT visual formatting properties. If a task needs any of those, hand off — `accotool-ai-customvisual-accomasterdata` / `accotool-ai-customvisual-accoplanning` for a visual's own configuration surface, `accotool-ai-semantic-model` for the modeling layer, the Microsoft plugins for generic mechanics — do not answer it from this skill.

**Where this layer sits:** the datamart views (§9) are the contract — the single surface everything downstream reads. This skill's job is to make what a visual writes back land somewhere sound, then prepare it (joins, business logic, calculations) so the semantic model can govern it and the report can show it back to the same user who typed it. `accotool-ai-solution-planning` owns that end-to-end picture and decides *whether* a given module should be built at all; this skill starts once that's settled.

**Confidence markers used throughout:**
🟢 Confirmed — verified against a real, currently-deployed database.
🟡 Working baseline — adopted as the standard going forward per an explicit decision, pending independent confirmation.
⚠️ Open — a known gap or unresolved question, flagged rather than guessed at.

**Several design decisions in this schema are easy to accidentally re-litigate or reverse** — see §13 for the standing rules most likely to get reintroduced by mistake (e.g. per-module writeback identities, audit-table shape, key-column renaming), and why each is settled rather than open.

**All build detail lives in [`references/accotool-ai-sql-schema-reference.md`](references/accotool-ai-sql-schema-reference.md)** — every DDL template, naming rule, and per-pattern instruction, confidence-marked the same way. This file is the procedure and the guard rails; that file is what the procedure points into. Read the relevant section of it before writing SQL, rather than working from the summaries here.

| Need | Reference section |
|---|---|
| Naming: schemas, tables, views, columns, procs, triggers; mandatory columns; sentinel dates and `_Int` keys | §3 |
| `accoTOOL$Base`: `Config_Connection`, `Config_Writeback`, `Log_Audit`, the optional shared `Dim_Version#AM` | §4 |
| Pattern A — dimension writeback (accoMASTERDATA) | §5 |
| Pattern B — fact writeback (accoPLANNING), incl. RAW→Current merge, the built-in comment column, cell locking | §6 |
| Pattern C — comment writeback (accoCOMMENT) | §7 |
| Writeback identity: check, provision, extend grants | §8 |
| Datamart views — the downstream contract | §9 |
| Altering an object that already exists or already holds data | §10 |
| Seed/demo data · verification checklist | §11 · §12 |

**The facts that span this layer and the next one live in `accotool-ai-solution-planning`'s [`references/accotool-ai-cross-layer-contracts.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md)** — read it before handing a build onward, and when a symptom appears somewhere other than where it was caused. The ones that reach into this skill: a datamart view's name *is* the model table's name (C1) and its type decides that table's storage mode (C2); in Pattern B the visual writes to RAW while the model reads Current, and `Config_Writeback` names the RAW table (C3); the mandatory `UpdatedBy`/`UpdateDateTime` columns are what accoPLANNING's `usernameColumn`/`timestampColumn` must be pointed at (C6); the `#AM`/`#AP`/`#AC` suffix must agree with `Config_Writeback.VisualCode` (C7); and the RAW→Current merge aggregation must match the visual's delta setting (C8 — §6.2 carries the detail, and getting it wrong is silent).

---

## 1. Architecture in One Picture

Three schema layers, created in this order, always:

```
Base (accoTOOL$Base)         → shared infrastructure: writeback identity, config, shared audit log
    ↓
Module (accoTOOL$ModuleName) → one per planning module: writeback tables, triggers, module views
    ↓
Datamart (dmAccoTOOL_Name)   → views only; the single contract downstream consumers read
```

🟢 **Hard rules:**
- Schema name delimiter: `$` for module (`accoTOOL$ModuleName`), `_` for datamart (`dmAccoTOOL_Name`) — never mixed.
- Modules never cross-reference each other's schemas. Only `accoTOOL$Base` and warehouse schemas may be referenced from a module.
- Datamart schema contains views only — no tables, procedures, or functions.
- `#` in any object name (table or trigger) must always be bracket-quoted in SQL: `[Fact_Name#AP]`.

Three writeback patterns cover everything:
- **Pattern A — Dimension writeback (accoMASTERDATA):** `Dim_{Name}#AM` + `vw_Dim_{Name}`. Audit trail is the single shared `accoTOOL$Base.Log_Audit` (§4.3) — there is no per-module audit table.
- **Pattern B — Fact writeback (accoPLANNING):** either a simple append-only `Fact_{Name}#AP`, or — when inputs need aggregating before display — `Fact_{Name}_RAW#AP` → `Fact_{Name}_Current` via an `AFTER INSERT` trigger with `COALESCE` merge logic.
- **Pattern C — Comment writeback (accoCOMMENT):** `Fact_{Name}_Comment#AC`, a simple append-only comment log.

### 1.1 Build order at a glance

1. Pre-flight discovery (§2) — inspect the target database before assuming anything about its state.
2. Resolve business parameters (§2.1) — module name, visual selection, data model scope.
3. Create the module schema, and the datamart schema if this is a new module.
4. Module objects (§5–§7) — per pattern, per entity in scope.
5. Writeback identity (§8) — reuse the existing shared user/role if one exists; provision it if not.
6. Populate `Config_Writeback` for the new module's writeback table(s) (§4.2).
7. Extend the shared identity's grants to cover the new schemas (§8).
8. Datamart views (§9).
9. Altering an already-existing object instead of creating a new one (§10) — different rules apply.
10. Seed / demo data if this is a fresh build (§11).
11. Verify (§12).

---

## 2. Before Writing Any SQL

### 2.1 Business discovery — condensed checklist

🟢 **This properly belongs to `accotool-ai-solution-planning`, which now exists** — it owns the business conversation, the module inventory, which entities are shared across modules, and what the report page has to say. Run it first; arrive here with these answers already in hand. (An earlier version of this section said no such orchestrator existed — that is no longer true, and resolving scope from scratch here instead of routing to it is now the wrong move.)

Keep the checklist below as a **second check, not the primary one**: if a build reaches this skill with any row unresolved, resolve it here rather than defaulting to a template — design decisions must come out of the business conversation, not out of habit. Anything that turns out to span more than this one module (a shared version dimension being the standard case, §4.4) belongs back in `accotool-ai-solution-planning` before it gets built here.

| # | Business question | What you're actually resolving |
|---|---|---|
| 1 | What do you call this planning/data process? | `{ModuleName}` |
| 2 | What does a user actually type in — a grid, or individual records? | Pattern A (AM) vs. Pattern B (AP) per entity |
| 3 | Does this relate to data that should live elsewhere (a warehouse, another system)? | What's writeback-owned vs. externally sourced |
| 4 | Can users work in multiple scenarios at once (e.g. "Budget 2026" vs. "Forecast Q3")? | Whether `Dim_Version#AM` (§4.4) is needed — most modules don't need this |
| 5 | Do you need a history of every change, or just the latest value? | Append-only fact vs. RAW+Current pattern |
| 6 | Do entries need free-text commentary? If so, is a single comment attached to a measure enough, or does it need its own independently-audited object? | accoPLANNING's built-in comment column (§6.4) vs. Pattern C's standalone accoCOMMENT table (§7) — not the same decision, see §6.4 |
| 7 | Does data entry need to be restricted or locked — by time period, planning version, or organizational area? | Whether accoPLANNING cell-locking support (§6.5) is needed, and which of its two approaches fits |

Make assumptions explicit and confirm them rather than blocking on missing information. Translate the business need into the technical pattern yourself — never ask a business user to do that translation.

### 2.2 Database pre-flight discovery — mandatory, every time

🟢 Never assume a target database is empty or that its objects follow any particular convention, even one described elsewhere in this document. Run this before designing anything:

```sql
-- What schemas already exist?
SELECT schema_name FROM information_schema.schemata; -- or sql_list_schemas

-- What's already in a schema you're about to touch or extend?
-- (sql_list_objects per schema, e.g. accoTOOL$Base, and any existing module/datamart schemas)

-- Does accoTOOL$Base already have the shared objects this skill expects?
SELECT * FROM [accoTOOL$Base].[Config_Connection];
SELECT * FROM [accoTOOL$Base].[Config_Writeback];
-- Does accoTOOL$Base.Log_Audit already exist? If not, it needs creating (§4.3) —
-- but check first; do not assume based on this document alone.

-- Does a writeback identity already exist?
SELECT name, type_desc, authentication_type_desc FROM sys.database_principals
WHERE type IN ('S','U','G') AND name NOT LIKE '##%' AND name NOT IN ('dbo','guest');

SELECT r.name AS role_name, m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON rm.role_principal_id = r.principal_id
JOIN sys.database_principals m ON rm.member_principal_id = m.principal_id;

-- What schema-level grants does an existing writeback role already have?
-- (adapt the schema/object join against sys.database_permissions — see §8)
```

If you find objects that don't match this document's expectations, **stop and ask** rather than silently building around them or silently overwriting them. A prior build in the same database is not automatically something to reuse — confirm intent before treating it as reusable.

---

## Safety rule that applies to every build

⚠️ **Before running any `ALTER` or `UPDATE` against an object that already holds rows, confirm the exact statement with the user first — do not treat it as a routine build step the way a fresh `CREATE TABLE` is.** State what will change, what depends on it, and what happens to existing data, then wait for an explicit go-ahead before executing. Reference §10 carries the full procedure: the mandatory pre-alteration discovery queries (§10.1), the ripple effect where a new column stays invisible until every dependent view is updated by hand (§10.2), and the checks that must precede a type or nullability change on populated data (§10.4).

Everything else in this skill only ever *creates* something new. This section is the one place where a mistake can destroy data or silently break a dependent.

---

## 13. Standing Rules That Are Easy to Reintroduce or Re-litigate by Mistake

- **Writeback identity: one shared user/role for the whole database, not one per module.** Confirmed in every real deployment this project has built (`writeback_user`/`writeback_role`, shared) — per-module identities add provisioning overhead with no observed benefit. Don't create a dedicated user per module.
- **`Config_Connection`: one row total, not one row per module.** Direct consequence of the above.
- **`Log_Audit`: one shared table in `accoTOOL$Base`, not one per module (`Log_{Name}_Audit`).** The shared design is the confirmed standard — existing per-module audit tables elsewhere in a given database are left as-is, not migrated, but new modules always use the shared table.
- **`Log_Audit.RowKey` is `NOT NULL`.** 🟡 Working assumption — see §4.3. The shared table never has a typed per-entity key column at all, only the generic `RowKey` — there's no separate "should this be nullable" question to solve per module.
- **`Config_Modules`, `vw_Config_Writeback`, and `sp_work_RefreshWritebackConfig` are not part of this schema.** None of the three exist in any real database this project has built against; every real `Config_Writeback` row is inserted by hand, and every real datamart `Config_Writeback` view filters `accoTOOL$Base.Config_Writeback` directly rather than through a `vw_Config_Writeback` layer. Leave them out unless a specific business case calls for reintroducing one.
- **Credential creation is performed directly via the SQL MCP, not handed to a human to run manually.** A deliberate, explicit decision for this project — see §8.2/§8.3 for the actual provisioning steps. Don't fall back to "an assistant should never create credentials" as a general instinct here.
- **This schema never mentions DAX, TMDL, or a visual's formatting pane.** That content belongs entirely to `accotool-ai-semantic-model` and the per-visual skills (`accotool-ai-customvisual-accomasterdata`, `accotool-ai-customvisual-accoplanning`) — hand off rather than answering a modeling or visual-formatting question from this skill.
- **Version-copy automation (`Config_VersionCopy`, `sp_VersionCopy`, `tvf_GetVersionsToCopy`) is not part of the default build.** Real, vendor-documented concepts, kept as an option under §4.4 for a module that actually needs multiple scenarios — not something every module gets by default.
- **Datamart dimension/fact views never rename the key column** (e.g. `BK_Employee#ID` stays `BK_Employee#ID`, not `EmployeeKey`). Neither the accoTOOL Solution Framework Documentation (external, not part of this repo) nor the accoOneDB documentation (a separate Accobat product) support renaming it — accoOneDB's own surrogate-key convention is different anyway (`SK_`/`FSK_` via a centralized keystore schema, unrelated to accoTOOL). A real pre-existing database object that happens to rename its keys is not the same thing as a documented convention — don't infer a renaming rule from one observed object.
- **`Log_Audit` holds exactly the five mandatory Audit Log columns from the accoTOOL Solution Framework Documentation §4.3, plus the `LogKey` surrogate PK — nothing else.** In particular, don't add differentiator columns (e.g. `ModuleName`/`SchemaName`/`TableName`) to try to solve cross-module identification of shared audit rows — accoMASTERDATA has no property that can populate arbitrary extra `NOT NULL` columns on its audit target, so a real writeback would fail the constraint. That cross-module identification problem remains genuinely unsolved; don't reintroduce columns to address it without first checking the writing visual can actually populate them.
