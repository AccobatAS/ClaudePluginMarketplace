---
name: accotool-ai-customvisual-accomasterdata
description: "Configure accoMASTERDATA (AM), accoTool's proprietary Power BI writeback visual for row-per-key data, in PBIR/PBIP. Use when editing dimension, meta-data or config tables — exactly one row per business key — or a fact table shaped like masterdata, one row per unique key combination (e.g. one row per project per budget version). Shape decides, not vocabulary: a Row-by-Column period matrix is accoPLANNING instead, however much the business calls it planning. Also a candidate mid-plan for another module, when a short list (version, status, category) may need a real maintained table rather than a hardcoded workaround — ask, never assume. Triggers: placing the visual, binding rowIds/measures, renaming a field without breaking writeback, wiring the connection or audit-log group, grid styling, dropdowns, shadow calculations, debugging an AM write/credential failure. Defers to accotool-ai-solution-planning for scope, accotool-ai-semantic-model for DAX, accotool-ai-sql-schema for the database."
metadata:
  author: Accobat A/S
  version: 0.3.0
---

# accoTool Custom Visual — accoMASTERDATA

## When accoMASTERDATA is the right visual

accoMASTERDATA handles **row-per-key** data. Two shapes, one underlying pattern:

1. **A dimension, meta-data, or config table** — exactly one row per business unit. Maintaining an Employee list, a status list, a set of planning versions.
2. **A fact table shaped like masterdata** — the same one-row-per-key shape, but the key is a *unique combination* rather than a single business unit. One row per project per budget version, for instance.

**Shape decides this, not vocabulary.** A Row×Column period-matrix grid — one row with many editable cells across periods — is `accotool-ai-customvisual-accoplanning`'s shape, no matter how the business phrases it. The reverse trap is the more common one: a request that says "planning" loudly can still be accoMASTERDATA's. Worked example — pipeline project planning, where a potential project's probability-weighted revenue (expected revenue × win probability) is stored one row per project per budget version. That is planning in business language and row-per-key in data terms, so it belongs here.

⚠️ A planning *version* list is a specific, already-settled case: it is a shared `accoTOOL$Base.Dim_Version#AM` table (`accotool-ai-sql-schema` §4.4), maintained through this visual, not invented per module. `accotool-ai-solution-planning` Step 3 owns that decision — don't re-derive it here.

**Scope:** accoMASTERDATA's own PBIR/JSON configuration surface only — data roles, object groups, property names, and write semantics as the *visual* itself exposes them. Does not own the semantic model backing a given module (table loading, relationships, storage modes, or the DAX inside any measure this visual binds to — that's `accotool-ai-semantic-model`'s job), the underlying database schema (`accotool-ai-sql-schema`), or generic PBIR/TMDL/Desktop mechanics (the Microsoft `powerbi-authoring` plugin). If a task needs any of those, hand off — don't answer it from here.

**Where this sits:** accoMASTERDATA is the *input surface* in the accoTOOL writeback chain — the user types here, it writes to the database, the warehouse prepares the result, the semantic model governs it, and it comes back onto the same page as context. `accotool-ai-solution-planning` owns that whole picture and the page it lives on. Two consequences worth carrying into every build here: a correctly-wired write path is not a finished module (the page still has to answer the business question the edit serves), and this visual is rarely alone on its page — configuring it well means configuring it to sit *next to* the visuals that give the edit its meaning.

**Two cross-layer facts that decide whether this visual's configuration is even correct**, both owned by `accotool-ai-solution-planning`'s [`references/accotool-ai-cross-layer-contracts.md`](../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md):
- **C4 — how a write target gets named is different here than in accoPLANNING.** accoMASTERDATA points writeback at a renamed field through an explicit `objects.connection[]` entry (§4); accoPLANNING infers it from the bound measure's own name. Never carry one visual's mechanism to the other.
- **C5 — every credential property must resolve to exactly one source row**, and a Desktop save undoes the binding every time (§5). The measure side belongs to `accotool-ai-semantic-model`; the failure surfaces here.

That file's symptom router is also the fastest route out of a failure whose cause is in another layer — which most of them are.

**All detailed findings live in [`references/accomasterdata.md`](references/accomasterdata.md)** — confidence-marked (🟢 confirmed / 🟡 working baseline / ⚠️ open) documentation of every behavior, property, and gotcha discovered so far. This file is the procedure for using that documentation; it isn't a substitute for reading it.

**Property catalogs.** Where a visual's subfolder includes a `*-schema.json` file (e.g. [`references/accomasterdata-schema.json`](references/accomasterdata-schema.json) for AM), that file is the authoritative superset of every Format-pane object/property the visual exposes — display name → internal property name, per object group, plus the JSON shape of any stringified-JSON property. The visual's own `.md` file only documents the subset that's been empirically built and confirmed (🟢/🟡/⚠️ markers). When a user's scenario calls for a property that's in the schema but not yet in the `.md`, treat it as real and reachable but unverified — check the schema for the correct property/selector name, then verify behavior against a live file before relying on it, and add the finding back to the `.md` once confirmed.

**Scope this skill never covers — hand off rather than answering from here:**

| Not this skill's | Whose it is |
|---|---|
| Whether this module should exist, what entities it shares with others, what the page must say | `accotool-ai-solution-planning` — ideally run *before* this skill, not after |
| accoPLANNING's configuration surface (`Row`/`Column`/`Measure`/`Transaction` roles, `planningConnection`, batch-write) | `accotool-ai-customvisual-accoplanning` — including for a "planning" scenario whose shape is a period matrix |
| Which DAX a bound measure contains and how it's authored — this skill only states what a property *requires* (e.g. "measure-bound, hosted off the visual's own table, returning this exact string shape") | `accotool-ai-semantic-model` |
| The database schema this visual writes into | `accotool-ai-sql-schema` |
| Building the ordinary Power BI visuals that give this grid its context, and generic PBIR/TMDL/Desktop mechanics | Microsoft `powerbi-authoring` / `semantic-model-authoring` plugins |

## Instructions

### Step 1: Never assume a supporting dimension exists — ask

Before designing around a missing concept — a version, status, category, or any other short list a plan needs to resolve a value from or write to — with a workaround (a disconnected parameter table, a hardcoded literal list, a literal column with no backing table), stop and ask the user two things: (a) does a table for this already exist in the model, and (b) if not, do they want one created as a proper, maintainable master-data table (this skill's job), or is a lightweight workaround intentional (a genuinely fixed, never-changing handful of values)? Don't infer the answer from how the requirement was phrased or from which visual the request was nominally about — a "version" or "category" mentioned in passing while planning a *different* visual (e.g. accoPLANNING) is exactly the kind of case this skill exists for. Defaulting to a workaround without asking is a routing miss, not a simplification — this applies even when no one has asked for accoMASTERDATA by name.

### Step 2: Read the reference file in full before touching anything

Read [`references/accomasterdata.md`](references/accomasterdata.md) start to finish before placing, binding, or modifying an accoMASTERDATA visual — don't skim for the one section that looks relevant. Several sections interact in non-obvious ways (e.g. field renaming in §4 changes which object group governs the write target; credential automation in §5 gets silently undone by an unrelated Desktop save).

### Step 3: Check the Format-pane schema for exact property names

[`references/accomasterdata-schema.json`](references/accomasterdata-schema.json) is a full dump of accoMASTERDATA's Format-pane property inventory. Use it to confirm an exact property/enum name before hand-authoring JSON — accoMASTERDATA is a proprietary visual with no CLI introspection (see the reference file's own §11), so this schema dump and the reference file are the only sources of truth available; don't guess a property name from memory or by analogy with accoPLANNING (the two visuals differ substantially in object group names, property names, and write semantics).

### Step 4: Place the visual, then bind rowIds/measures

Follow the reference file's §1 (placement) and §2–§3 (data roles, editability defaults) in order. Every column placed in the `measures` well is editable by default — there is no need to opt fields in, only (occasionally) to restrict one back down.

### Step 5: Wire the connection and, if needed, the audit log

Bind the `connection` object group per the reference file's §5 — every credential property must be measure-bound (never a literal), except `authenticationMethod` and `encryptedUser`/`encryptedPassword`, which must stay absent entirely. This skill only states which property needs which measure; the measure's own DAX belongs to `accotool-ai-semantic-model`. The separate audit-log block (§6) is optional and independent of core writeback.

### Step 6: Validate → reload → screenshot, then verify with a real write

Use the standard PBIR edit → validate → reload → screenshot loop (see the Microsoft `powerbi-authoring` plugin for the generic mechanics) after every change. After any Desktop save, re-check the credential properties specifically (§5) — a save silently reverts the automated-credential state every time, with no error, and this is easy to miss until the next write fails.

### Step 7: Record what you learn

If a build surfaces a new confirmed fact, a contradiction of something already in the reference file, or a new open question, update [`references/accomasterdata.md`](references/accomasterdata.md) — keep its confidence markers honest (don't promote 🟡/⚠️ to 🟢 without independent verification) rather than leaving new knowledge only in conversation history.
