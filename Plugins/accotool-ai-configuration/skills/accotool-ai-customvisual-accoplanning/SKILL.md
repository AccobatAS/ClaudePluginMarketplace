---
name: accotool-ai-customvisual-accoplanning
description: "Configure accoPLANNING (AP), accoTool's proprietary Power BI writeback visual for period-matrix planning, in PBIR/PBIP. Use when one axis crosses another and every intersection is editable — classically accounts, employees or projects down the rows and periods across the columns — or when planning one measure repeatedly across periods, capturing a per-cell comment, or persisting a value derived from other bound measures (a shadow calculation). Shape decides, not vocabulary: one row per business key, including a fact table with one row per unique key combination, is accoMASTERDATA instead. Triggers: placing the visual, binding Row/Column/Measure/Transaction/NonWriteableMeasures/Comments, classifying a measure writeable or non-writeable, wiring planningConnection, batchRows, debugging a NULL foreign-key INSERT or a calculation that never persisted. Defers to accotool-ai-solution-planning for scope, accotool-ai-semantic-model for DAX, accotool-ai-sql-schema for the database."
metadata:
  author: Accobat A/S
  version: 0.5.0
---

# accoTool Custom Visual — accoPLANNING

## When accoPLANNING is the right visual

accoPLANNING handles a **Row×Column period matrix** — one axis crossing another, every intersection editable:

1. **A cross-tab entry grid** — accounts, employees, projects or cost centres down the rows; periods across the columns; an amount in each cell.
2. **The same measure planned repeatedly across periods**, where year/month form a drill hierarchy on an axis rather than flat attributes on a row.
3. **A value plus its per-cell comment**, or a value derived from other bound measures that must itself persist (a shadow calculation, §5 — the only calculation type here that writes back).

**Shape decides this, not vocabulary.** If the data is one row per business key — a dimension, a config table, or a fact table where one row is one unique key combination (one row per project per budget version, say) — that is `accotool-ai-customvisual-accomasterdata`'s shape, however much the business calls it planning. The reverse holds too: a request that never says the word still belongs here if a user is editing a measure across periods on a grid.

**Scope:** accoPLANNING's own PBIR/JSON configuration surface only — data roles, object groups, property names, and write semantics as the *visual* itself exposes them. Does not own the semantic model backing a given module (table loading, relationships, storage modes, or the DAX inside any measure this visual binds to — that's `accotool-ai-semantic-model`'s job), the underlying database schema (`accotool-ai-sql-schema`), or generic PBIR/TMDL/Desktop mechanics (the Microsoft `powerbi-authoring` plugin). If a task needs any of those, hand off — don't answer it from here.

**Where this sits:** accoPLANNING is the *input surface* in the accoTOOL writeback chain — the user types here, it writes to the database, the warehouse prepares the result, the semantic model governs it, and it returns to the same page as context. `accotool-ai-solution-planning` owns that whole picture and the page it lives on. Two consequences worth carrying into every build here: a correctly-wired write path is not a finished module (the page still has to answer the business question the planning serves — a planning grid with no actuals, prior version, or variance beside it is an unfinished page, not a minimal one), and this visual is rarely alone on its page, so configuring it well means configuring it to sit *next to* the visuals that give the numbers their meaning.

**All detailed findings live in [`references/accoPLANNING.md`](references/accoPLANNING.md)** — confidence-marked (🟢 confirmed / 🟡 working baseline / ⚠️ open) documentation of every behavior, property, and gotcha discovered so far. This file is the procedure for using that documentation; it isn't a substitute for reading it.

**Three cross-layer facts that decide whether this visual's configuration is even correct**, all owned by `accotool-ai-solution-planning`'s [`references/accotool-ai-cross-layer-contracts.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md):
- **C4 — the bound measure's own name is the write target** for every `Measure`-type projection (§3), which reaches back into `accotool-ai-semantic-model` because the measure itself has to be renamed. accoMASTERDATA works differently; never carry its mechanism here.
- **C3 — in the RAW→Current pattern this visual writes to a different table than the model reads.** `Config_Writeback` names the RAW table; the grid renders the datamart view over Current.
- **C8 — the delta setting on a shadow calculation (§5) is also a database decision.** The RAW→Current merge has to sum deltas rather than take a latest or maximum value, or the stored numbers are quietly wrong with no error anywhere.

That file's symptom router is also the fastest route out of a failure whose cause is in another layer — which most of them are, including this visual's signature `Cannot insert the value NULL` error when a page's version slicer, rather than the binding, is what's blank ([`accotool-ai-page-composition.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-page-composition.md) §2).

**Scope this skill never covers — hand off rather than answering from here:**

| Not this skill's | Whose it is |
|---|---|
| Whether this module should exist, what entities it shares with others, what the page must say | `accotool-ai-solution-planning` — ideally run *before* this skill, not after |
| accoMASTERDATA's configuration surface (`rowIds`/`measures` roles, the `connection` and audit-log groups) | `accotool-ai-customvisual-accomasterdata` — including any supporting master-data table this module turns out to need |
| Which DAX a bound measure contains and how it's authored — this skill only states what a property *requires*, including a measure's required *name* (§3) | `accotool-ai-semantic-model` |
| The database schema this visual writes into | `accotool-ai-sql-schema` |
| Building the ordinary Power BI visuals that give this grid its context, and generic PBIR/TMDL/Desktop mechanics | Microsoft `powerbi-authoring` / `semantic-model-authoring` plugins |

## Instructions

### Step 1: Never assume a supporting dimension exists — ask

A missing short list that a role needs to resolve a key from — most often something the `Transaction` role would need (§3): a version, status, category — must not be worked around with a disconnected parameter table, a hardcoded list, or a literal column with no backing table until the user has been asked (a) whether a table for it already exists and (b) whether they want a proper maintained one. This rule is owned by `accotool-ai-solution-planning` Steps 2–3, which should have settled it before this skill starts, and by `accotool-ai-customvisual-accomasterdata` Step 1, which governs building the table. **If neither has happened, ask here rather than defaulting to a workaround** — a "version" mentioned in passing while planning is exactly the case this catches, and defaulting is a routing miss rather than a simplification.

⚠️ A supporting dimension that turns out to be needed is not only a data question — if its key gets written but it isn't on an axis, the page's slicer for it becomes part of the write path and must be single-select with a default ([`accotool-ai-page-composition.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-page-composition.md) §2).

### Step 2: Read the reference file in full before touching anything

Read [`references/accoPLANNING.md`](references/accoPLANNING.md) start to finish before placing, binding, or modifying an accoPLANNING visual — don't skim for the one section that looks relevant. The visual's behavior has enough non-obvious interactions (e.g. the `Transaction` role's naming rule in §3) that a partial read is a common source of a repeat failure someone already solved.

### Step 3: Check the Format-pane schema for exact property names

[`references/accoplanning-schema.json`](references/accoplanning-schema.json) is a full dump of accoPLANNING's Format-pane property inventory (every settings group, property, and default). Use it to confirm an exact property/enum name before hand-authoring JSON — accoPLANNING is a proprietary visual with no CLI introspection (see the reference file's own §8), so this schema dump and the reference file are the only sources of truth available; don't guess a property name from memory or by analogy with accoMASTERDATA. Note its limits too: it doesn't list enum values for dropdown-type properties, and it has no entry at all for the shadow-calculation storage property (reference file §5) — some things can only be learned by reading back a real file after a Desktop-UI action, not from this schema.

### Step 4: Place the visual, then bind Row/Column/Measure/Transaction/NonWriteableMeasures/Comments

Follow the reference file's §1 (placement) and §2–§3 (data roles) in order. In particular, before binding any dimension into `Row` or `Column`, work out whether accoPLANNING needs a matching `Transaction`-role entry for it (reference file §3) — this is the single most common way a new build fails, and it fails with a real but easy-to-misread SQL error rather than a clear "you forgot X" message. When a measure needs to be Non-writeable rather than Writeable, its projection belongs in the separate `NonWriteableMeasures` role, not a property on the ordinary `Measure` role (reference file §2) — this is not guessable from the Format-pane schema alone. A per-cell comment binds through its own role, `Comments`, following the same naming rule as any other measure-type projection (reference file §2).

### Step 5: Wire the connection

Bind `planningConnection`'s properties per the reference file's §4. Every credential/connection property must be measure-bound (never a literal) except the literal exceptions the table there calls out — this skill only states which property needs which measure; the measure's own DAX belongs to `accotool-ai-semantic-model`. Re-check this after every Desktop save regardless — a save reliably reverts the automated-credential state (reference file §4), so this isn't a one-time setup step. If the module writes more than one bound field per cell (e.g. a value plus a comment), also set `batchRows: true` — the default (`false`) writes each edited field as its own separate, incomplete row instead of combining same-cell edits into one (reference file §4).

### Step 6: Build a shadow calculation, if the module needs one

If a value needs to be computed from other bound measures *and* persisted to the writeback table, it has to be a shadow calculation — the reference file's other two calculation types are display-only (§5). Classify the relevant measures first (Step 4), then build the formula through Desktop's Advanced Options panel, not by hand-authoring JSON from scratch — the storage format (`objects.calculations`, a single delimited string holding every calculation) is only confirmed safe to *edit* (e.g. to remove a calculation via Advanced Options → Calculations → Shadow calculations → Calculation overview, or by trimming the string directly), not to author from nothing.

### Step 7: Validate → reload → screenshot, then verify with a real write

Use the standard PBIR edit → validate → reload → screenshot loop (see the Microsoft `powerbi-authoring` plugin for the generic mechanics) after every change. Structural success (no validation errors, visual renders) is not the same as writeback working — where possible, confirm with an actual cell edit and check the destination table directly, since accoPLANNING can render a perfectly normal-looking grid while every write silently fails. If a shadow calculation is involved, check the destination table specifically for whether the *calculated* value landed correctly, not just whatever was typed directly — a grid that renders fine can still have a calculation that never fired (reference file §5, §9).

### Step 8: Record what you learn

If a build surfaces a new confirmed fact, a contradiction of something already in the reference file, or a new open question, update [`references/accoPLANNING.md`](references/accoPLANNING.md) — keep its confidence markers honest (don't promote 🟡/⚠️ to 🟢 without independent verification) rather than leaving new knowledge only in conversation history.
