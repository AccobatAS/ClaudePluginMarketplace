---
name: accotool-ai-semantic-model
description: "Author the Power BI semantic-model layer for accoTool writeback solutions — the governance layer, where writeback data is defined and related alongside the rest of the business model. Covers loading accoTool datamart views as tables, storage mode per view type, the inline Sql.Database partition pattern, date-table sourcing, the dedicated _Measures table, the connection-measure bridge from Config_Connection/Config_Writeback into visual-bound credentials, writeback-critical naming constraints, and model-view layout. Use when: bringing datamart views into a model, building relationships, deciding on a date table, organising measures, authoring a measure that feeds a visual property, or diagnosing a writeback credential failure traced to DAX. Defers to the Microsoft semantic-model-authoring plugin for generic modelling, to accotool-ai-customvisual-accomasterdata or accotool-ai-customvisual-accoplanning for which property a measure binds to, and to accotool-ai-solution-planning for scope."
metadata:
  author: Accobat A/S
  version: 1.6.0
  mcp-servers:
    - powerbi-modeling-mcp
---
# accoTool Semantic Model — Project-Specific Handoff

**Scope:** the project-specific facts a generic TMDL/semantic-model skill has no way to infer on its own — table loading/naming, relationships, storage-mode assignment, date-table sourcing, measure-folder organization, the connection-measure pattern that bridges `Config_Connection`/`Config_Writeback` into visual-bound credentials, model-view layout, and known gotchas specific to this architecture. For generic semantic-model mechanics (creating tables, columns, generic relationship authoring, deploying, refreshing) defer entirely to the Microsoft `semantic-model-authoring` plugin — do not duplicate that here. For which literal visual property each measure binds to (e.g. `databasePassword` vs. `password`), defer to the per-visual skill — `accotool-ai-customvisual-accomasterdata` or `accotool-ai-customvisual-accoplanning` — since that mapping is product-specific, not modeling-specific, and the two visuals genuinely differ (accoMASTERDATA's `connection` group vs. accoPLANNING's `planningConnection`, with different property names in each).

**One owner per fact:** this skill owns the DAX/measure side of the credential bridge, storage-mode assignment, relationships, date-table sourcing, and measure/model organization. It does not own `Config_Connection`'s shape (that's `accotool-ai-sql-schema` §4.1), which visual property consumes a given measure (that's the per-visual skill), or whether a module should exist and what its page has to say (that's `accotool-ai-solution-planning`). Cross-reference those, don't restate them here. If this skill and `accotool-ai-sql-schema` ever appear to disagree on modeling-layer content, this file is the current owner and should win.

**Confidence markers** — same convention as `accotool-ai-sql-schema`:
🟢 Confirmed — verified against a real, currently-deployed build.
🟡 Working baseline — adopted, pending independent confirmation.
⚠️ Open — a known gap or unresolved question.

**All modeling detail lives in [`references/accotool-ai-semantic-model-reference.md`](references/accotool-ai-semantic-model-reference.md)** — confidence-marked the same way. This file is the procedure and the operational guard rails; that file is what the procedure points into. §11 below is the exception: it stays here because a missing gotcha there can cost a live model.

| Need | Reference section |
|---|---|
| Loading datamart views as model tables, and why names must match the view exactly | §1 |
| Storage mode per view type — and why an Import dimension must never relate to a DirectQuery fact | §2 |
| Relationships: star-schema shape, cardinality, storage-mode compatibility | §3 |
| Partition / M pattern — inline `Sql.Database(...)`, never a shared named expression | §4 |
| Date table: detecting accoOneDB, importing vs. building | §5 |
| The connection-measure bridge — `Config_Connection` → visual-bound credentials | §6 |
| Writable measure patterns: conditional derivation, defaults for never-written rows | §7 |
| Measure organization, the dedicated `_Measures` table, and why visual-bound measures must live there | §8 |
| Naming constraints that are load-bearing for writeback | §9 |
| Model view layout via `diagramLayout.json` | §10 |

**The facts that span this layer and its neighbours live in `accotool-ai-solution-planning`'s [`references/accotool-ai-cross-layer-contracts.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md)** — read it before wiring a module end to end, and whenever a symptom shows up in a layer other than the one that caused it. The ones that reach into this skill: view name = table name (C1) and view type = storage mode (C2); `Config_Writeback` names the *write* target, which in Pattern B is a different table than the one this model loads (C3); a measure's own name is load-bearing for accoPLANNING's write target but not accoMASTERDATA's (C4); every hop of the credential bridge must resolve to exactly one row (C5); and any measure a visual property binds to must be hosted on `_Measures` (C9).

## Build order

1. **Load the datamart views** as model tables, names matching the source views exactly (§1). If a name doesn't match, that's upstream drift to trace back to `accotool-ai-sql-schema`, not something to reconcile here.
2. **Assign storage modes** by view type — DirectQuery for writeback facts, Dual for dimensions, Import for config (§2). Getting this wrong produces a weak relationship that silently breaks filter propagation.
3. **Build relationships** (§3), respecting the storage-mode compatibility rule from step 2.
4. **Settle the date table** (§5) — detect accoOneDB before deciding whether to import or build one; if only one of the two signals is present, ask rather than guess.
5. **Create the dedicated `_Measures` table**, then the connection-measure bridge (§8, §6). ⚠️ Never use a bare `SELECTEDVALUE` for a `Config_Connection` lookup — it returns `BLANK` the moment a second row exists, which is a writeback failure with no visible error. Always `CALCULATE(SELECTEDVALUE(...), filter)`.
6. **Author any other visual-bound measure** on that same `_Measures` table (§8) — hosting one on a data table has been confirmed to make the consuming property vanish from the visual's Format pane. The exact string shape a property expects belongs to the consuming visual's own skill, not here.
7. **Lay out the model view** (§10) if the build should match the organization's convention.
8. **Persist to disk** via `ExportToTmdlFolder`, then fix `database.tmdl`'s name — it gets clobbered by every export (§4). Verify with a DAX query, not a reload (§11).

---

## 11. Known Environment Gotchas

⚠️ Power Query Editor throws `The key didn't match any rows in the table` when opened against a Dual or DirectQuery table. Data loads and refreshes normally regardless — this appears to be a limitation of the editor's preview engine itself, not a real data problem. Root cause unconfirmed; don't chase it as if it indicates broken data.

🟢 **How live model changes actually reach disk — and why `reload` is not part of that path.** Table/column/measure changes pushed via this skill's MCP tools (`table_operations`, `column_operations`, `measure_operations`) take effect immediately in Desktop's live session — verify with a `dax_query_operations` `Execute` call, not by reloading. To persist that state to the on-disk TMDL files, call `database_operations` `ExportToTmdlFolder` pointed at the model's own `definition` folder, then fix `database.tmdl`'s name (§4 — it gets clobbered by every export, and separately by every Desktop-driven save). `powerbi-desktop reload` is only for picking up **file-based** edits (`diagramLayout.json`, or `visual.json`/`report.json` on the report side) — it is not a way to "refresh" or "sync" the semantic-model side, and should not be called just because a model change was made.

🟢 **`powerbi-desktop reload` can wipe the live model instead of restoring it.** After exporting a live model to TMDL and calling `reload`, the live session was found completely empty (0 tables) — `reload` does not reliably re-import the semantic-model side of a PBIP, even though the correct TMDL files were sitting on disk. Recovery is re-running the same `table_operations Create` calls directly against the live connection — **not** `database_operations ImportFromTmdlFolder`, which creates a separate, disconnected *offline* connection rather than pushing into the live Desktop session (confirmed via `connection_operations ListConnections` showing distinct offline and live connections after trying it).

⚠️ **A live push immediately after a reload can crash Desktop.** Recreating tables right after a reload had just wiped them triggered a real Desktop crash (`Microsoft.Mashup.Host.Document.Storage.InvalidPackageReferenceException: Could not find a PackageSession for the given sessionID`) — a stale Mashup/Power Query evaluation session left over from the reload, now out of sync with the freshly-rebuilt model. If a reload's effect on the model is uncertain, verify state (`table_operations List` or a DAX query) before pushing further changes, rather than immediately retrying.

🟢 **Two Desktop windows can be open on the same PBIP at once**, each with its own process ID and its own local AS instance/port. `connection_operations ListLocalInstances` and `powerbi-desktop status` can disagree on which process is "the" one, and a stale window left over from an earlier crash can survive a `Stop-Process` call issued moments earlier (it may have already exited on its own). Always re-check before assuming a kill or reload targeted the window the user is actually looking at — ask which window is real if more than one is reported.
