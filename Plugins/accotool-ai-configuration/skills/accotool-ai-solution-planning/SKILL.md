---
name: accotool-ai-solution-planning
description: "Establish the scope of an accoTOOL FP&A solution — which modules it contains, how they interconnect, which entities are shared across them, and what each report page has to say — before any writeback visual is chosen. accoTOOL brings reporting and editing of the same data together in one place, so the deliverable is a page that solves a business problem, not a bare data-entry grid. Use when: a new accoTOOL module or FP&A scenario is described (even a single one — the point is surfacing whether it belongs to something bigger); an entity a module needs (a version, status or category list) may or may not exist, and gets checked against the real database before anything is built; several modules should share one entity rather than each inventing its own; or a page's context visuals need deciding alongside the input surface. Run before accotool-ai-customvisual-accomasterdata, accotool-ai-customvisual-accoplanning, accotool-ai-sql-schema and accotool-ai-semantic-model — it hands off to them."
metadata:
  author: Accobat A/S
  version: 0.3.0
---

# accoTool Solution Planning

**Scope:** the accoTOOL FP&A solution as a whole — its module inventory, the entities shared across modules, and what each report page has to say. This skill exists to run *before* the layer-specific skills — it hands off to them once the frame is established, it doesn't replace them.

**What this skill hands off, and to whom:**

| Not this skill's | Whose it is |
|---|---|
| A visual's own PBIR/JSON configuration — data roles, object groups, write semantics | `accotool-ai-customvisual-accomasterdata` once a piece's shape is row-per-key; `accotool-ai-customvisual-accoplanning` once it's a Row×Column period matrix |
| DAX, relationships, storage modes — this skill says an entity *needs* modelling, never how | `accotool-ai-semantic-model` |
| Table and column design — this skill says a table is *needed*, never its shape | `accotool-ai-sql-schema` |
| Authoring the ordinary Power BI visuals that carry a page's context — this skill decides what the page must *say* (Step 6) and hands over a page spec, not a built page | Microsoft `powerbi-report-design` / `powerbi-report-authoring` |

**Triggered even by a single-module request.** "I want account planning by version" is in scope precisely because the point is to surface whether it's one piece of something larger. A supporting entity whose existence or ownership is unclear always triggers this skill first — `accotool-ai-customvisual-accomasterdata`'s own "never assume a supporting dimension exists" step catches the same gap in isolation, but this skill runs *before* it, not instead of it. Once the frame and shared entities are settled and the only open question is one visual's technical configuration, this skill is done — hand over.

**Why accoTOOL solutions exist in Power BI at all:** to bring reporting on data and writeback editing of that same data together in one place, not as two separate tools. Keep that in view when scoping a module — its purpose is rarely "just" a writeback grid; it usually sits alongside standard Power BI reporting on the same underlying tables. This also means the database is very often not a blank slate: a dimension or fact table a module needs may already exist, built for reporting and never yet connected to a writeback visual. Reusing it is the default — a new table is the exception that needs justifying, not the other way around.

## The accoTOOL writeback chain

**This skill owns this picture.** Every other accoTOOL skill owns one layer of it and should cross-reference here rather than restating it:

1. **Report — the application layer.** Where a user reads context and types input. An accoTOOL visual captures the input; the ordinary Power BI visuals around it supply the context that makes that input a *decision* rather than data entry.
2. **accoTOOL visual — the input surface.** Captures what the user types and writes it back to the database (`accotool-ai-customvisual-accomasterdata` / `accotool-ai-customvisual-accoplanning`).
3. **Database / data warehouse — the logic layer.** Stores the writeback, then applies business logic, joins, and calculations to prepare it for Power BI (`accotool-ai-sql-schema`).
4. **Semantic model — the governance layer.** Governs data, relationships, and definitions, and how the writeback data interconnects with the rest of the business model (`accotool-ai-semantic-model`).
5. **Back to the report.** The prepared, modelled data lands back on the page — next to the input surface that produced it.

It is a **loop, not a pipeline**: what a user types re-enters the same page as modelled, calculated context. A decision at any one layer is a decision about the whole loop, which is why scope gets settled here before any single layer starts building.

**A writeback report is an application, not a data-entry form.** The goal is almost never to capture writeback data for its own sake — it is to solve a concrete business problem. That is why an accoTOOL visual rarely belongs alone on a page: the surrounding visuals answer the question and build the case; the accoTOOL visual is where the user acts on it. One side creates context, the other captures the response. A page holding nothing but a writeback grid usually means the business problem hasn't been articulated yet — go back to Step 6 rather than shipping a bare input surface. The bar for a finished module is a complete, compelling visual story that a business user can act inside, not a working write path.

**Three reference files, each with a distinct job** — all confidence-marked (🟢 confirmed / 🟡 working baseline / ⚠️ open) the same way accoMASTERDATA's and accoPLANNING's own reference files are:

| File | What it holds | Read it when |
|---|---|---|
| [`references/accotool-ai-solution-architecture.md`](references/accotool-ai-solution-architecture.md) | the running record of known/planned modules, shared entities, and page compositions | starting any conversation — it's what makes the next one resume instead of rediscover. Empty until the first real solution gets discussed |
| [`references/accotool-ai-cross-layer-contracts.md`](references/accotool-ai-cross-layer-contracts.md) | the invariants that span two layers and therefore belong to no single layer skill, plus a symptom → owner router | wiring a module end to end, handing off between layers, or debugging anything (the symptom almost never appears in the layer that caused it) |
| [`references/accotool-ai-page-composition.md`](references/accotool-ai-page-composition.md) | how an accoTOOL visual lives on a page beside the visuals that give it meaning — including where filter context becomes a write-path correctness concern | Step 6, and any time a page is being specified rather than a visual configured |

**The contracts file is the one other skills should be pointed at.** Each layer skill is correctly scoped to its own layer; the facts that only exist *between* layers had no owner until that file, and they are where builds actually break.

## Instructions

### Step 1: Establish the module inventory, not just the module in front of you

Ask what accoTOOL modules already exist (built or in production) and what's planned or anticipated, even if only mentioned in passing. A request framed as one isolated module ("account planning by version") is very often one piece of a larger FP&A solution (e.g. account planning alongside employee planning, project planning, sharing the same version concept) — don't scope the conversation to only the module named first. If the user hasn't said whether more is planned, ask rather than assume the scope stops at what was literally described.

### Step 2: Check what the database already has before assuming anything needs to be built

For anything a module needs (a version, currency, org unit, status, or any other supporting entity), check whether a dimension or fact table already exists for it — consult `accotool-ai-sql-schema` for the actual schema, or ask the user directly what's already there — before treating it as something to create. Existing structure is the default to reuse, not a coincidence to work around: a table built for reporting that was never wired up to a writeback visual is still the right table, not a reason to build a parallel one. Only once existence has actually been checked (not assumed either way) does the question become "does this need to be created" — never skip straight to that question.

### Step 3: Identify entities that are — or should be — shared across modules

For anything a module needs that could plausibly be reused by another module (a version, currency, org unit, status, or similar cross-cutting concept), ask whether it should be modeled once, centrally, rather than let a single module's implementation quietly decide its shape. A dimension built by accident inside one module's scope is hard to retrofit into a shared one later — this decision belongs here, before any visual-level work starts.

🟢 **Some shared entities are already settled by convention — check before designing one from scratch.** The clearest case is a **planning version/scenario** ("Budget 2026" vs. "Forecast 3+9" vs. "Forecast 9+3"): `accotool-ai-sql-schema` §4.4 already specifies it as `accoTOOL$Base.Dim_Version#AM` — living in the **shared base schema, not a module schema**, precisely because a scenario concept spans modules, and carrying the `#AM` suffix because it is maintained as accoMASTERDATA master data. So a version list is neither a new design question nor a candidate for a disconnected parameter table: the convention exists, it is shared by design, and it is maintained through a small accoMASTERDATA grid. Only build it when discovery actually calls for multiple concurrent scenarios (`accotool-ai-sql-schema` §2.1, question 4) — most modules don't need one — but when it is needed, follow that convention rather than inventing a per-module variant.

### Step 4: Hand off entity creation, don't do it here

Once an entity is confirmed to not already exist (per Step 2) and needs to be built, this skill doesn't build it. If it looks like proper master data (one row per business key), hand off to `accotool-ai-customvisual-accomasterdata` (its own Step 1 governs the "does it already exist, should it be created" conversation at the implementation level — redundant with Step 2 here by design, as a second check, not a contradiction). The underlying table and semantic-model work belong to `accotool-ai-sql-schema` and `accotool-ai-semantic-model` respectively. This skill's job ends at "this entity should exist and be shared this way" — not at building it.

### Step 5: Classify each module's data shape, then route it

Once the overall frame and shared entities are settled, classify each individual module by its writeback shape: row-per-key (a dimension, or a fact table where one row is one unique key combination) routes to `accotool-ai-customvisual-accomasterdata`; a Row×Column period-matrix planning grid routes to `accotool-ai-customvisual-accoplanning`. Those skills' own frontmatter triggers take over from here — this skill doesn't re-derive their routing logic, it just makes sure the right shape question gets asked with the full picture in view.

⚠️ **accoCOMMENT (AC) is a third writeback visual with no configuration skill yet.** `accotool-ai-sql-schema` §7 specifies its database side (Pattern C, `Fact_{Name}_Comment#AC`) and the naming convention reserves the `AC` code, but nothing in this skill set documents how to place or configure the visual itself. Two different things get confused here, and `accotool-ai-sql-schema` §6.4 draws the line: accoPLANNING has its own **built-in per-cell comment** (just a `Comment` column on the planning fact — usually the simpler answer), which is *not* the same as a standalone accoCOMMENT object with its own independently-audited table. Route a comment requirement to accoPLANNING's built-in feature where that fits; if a standalone accoCOMMENT visual is genuinely needed, say plainly that its configuration is undocumented and treat the build as exploratory rather than guessing by analogy with AM or AP — the three visuals have already been found to differ substantially in object-group names, property names, and write semantics.

### Step 6: Design the page as an application, not just an input surface

Before handing a module off to a visual skill, settle what the *page* has to do — this is where the "complete and compelling visual story" from the top of this file actually gets decided. Every page has three jobs: **answer** the question the user needs settled before they can responsibly type anything, **act** (the accoTOOL visual), and **confirm** — a visual reading the writeback data back so the user sees what their own edit did. A page with only the middle one is unfinished, not minimal.

**Work through [`references/accotool-ai-page-composition.md`](references/accotool-ai-page-composition.md) here** rather than improvising the composition. It carries the part a generic report skill has no way to know: that a slicer scoping a written dimension is part of the write path and must be single-select with a default (a multi-select version slicer produces the same `NULL` foreign-key failure as a missing binding), which interactions are safe into the grid, and how to establish that a write actually becomes visible on the page. It ends in a seven-point page spec — produce that.

This skill owns the *intent*. It does not own the mechanics: building the ordinary Power BI visuals that carry the context is generic report authoring (defer to the Microsoft `powerbi-report-design` / `powerbi-report-authoring` skills), and configuring the accoTOOL visual itself belongs to its own skill (Step 5). Carry the page spec's accoTOOL-specific constraints across explicitly — a generic report skill cannot infer them.

### Step 7: Record the solution architecture

Update [`references/accotool-ai-solution-architecture.md`](references/accotool-ai-solution-architecture.md) with the module inventory, any shared-entity decisions, and the page composition from Step 6 — which modules exist/are planned, which entities are shared and by which modules, which skill owns each, and for each page: its business question, its context visuals, and which of its slicers are write-scoping. Keep confidence markers honest, the same convention as the other accoTOOL skills. A module recorded without its page composition is unfinished, not merely undocumented. This is what lets the next conversation start from the established frame instead of rediscovering it.
