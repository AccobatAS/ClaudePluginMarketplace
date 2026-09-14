# accoTOOL Solution Architecture — Module Inventory & Shared Entities

**Status:** empty — nothing recorded yet. Populate this as real solutions get discussed and built, per `accotool-ai-solution-planning`'s own Step 7.

**Sibling references:** [`accotool-ai-cross-layer-contracts.md`](accotool-ai-cross-layer-contracts.md) holds the invariants that span layers (and the symptom → owner router); [`accotool-ai-page-composition.md`](accotool-ai-page-composition.md) holds how a page is composed around an input surface. This file holds only *what has actually been decided for real solutions* — it is a record, not guidance.

**Confidence markers:**
🟢 Confirmed — an existing, built module or entity.
🟡 Working baseline — planned or agreed, not yet built.
⚠️ Open — mentioned as a possibility, not yet decided.

---

## Modules

*(None recorded yet. Each entry: module name, business purpose, writeback shape (row-per-key vs. Row×Column matrix), which visual implements it, status.)*

---

## Shared entities

*(None recorded yet. Each entry: entity name, which modules use it, whether it exists as a real table yet, and where it's modeled — e.g. `accotool-ai-sql-schema`/`accotool-ai-semantic-model` — or whether it's still an open question.)*

**Settled by convention before anything is recorded here:** a planning version/scenario is `accoTOOL$Base.Dim_Version#AM` — shared base schema, maintained as accoMASTERDATA master data (`accotool-ai-sql-schema` §4.4). Record a module's *use* of it here; don't re-decide its design.

---

## Page compositions

*(None recorded yet. Each entry: which module's page, the business question it answers, the context visuals that answer it, where the accoTOOL input surface sits within that, which slicers are write-scoping vs. view-scoping, and how a write was confirmed to become visible — the seven-point spec from [`accotool-ai-page-composition.md`](accotool-ai-page-composition.md) §6. A module recorded above without a composition here is unfinished, not merely undocumented.)*

---

## Solution-level open items

Known gaps that span the whole solution rather than any one module. Flag them in discovery rather than answering by analogy; move one out of this list only when it has actually been resolved against a real build.

⚠️ **accoCOMMENT (AC) has no configuration skill.** Its database side is specified (`accotool-ai-sql-schema` §7, Pattern C) and the `AC` code is reserved, but nothing documents how to place or configure the visual. Route comment requirements to accoPLANNING's built-in per-cell comment where that fits (`accotool-ai-sql-schema` §6.4, `accotool-ai-customvisual-accoplanning` §2); if a standalone accoCOMMENT object is genuinely needed, say plainly that its configuration is undocumented and treat the build as exploratory — the three visuals already differ substantially in object-group names, property names, and write semantics, so guessing by analogy is not safe.

⚠️ **Nothing verified in the Power BI Service.** Every finding across these skills comes from Power BI Desktop. Gateway requirements for the DirectQuery writeback connection, Service-side credential handling against the measure-bound bridge, and licensing are all untested. A Desktop-verified build is not a shipped build.

⚠️ **Production credential hardening has no owner.** The plaintext `DBPassword` in `Config_Connection`, its exposure through the datamart view, and its presence inside the semantic model are each individually flagged as an accepted PoC trade-off (`accotool-ai-sql-schema` §4.1/§9, `accotool-ai-semantic-model` §6) — but no skill owns the path to a production-safe alternative. Raise it before any module goes live.

⚠️ **RLS and writeback together are unexamined.** What happens when a row-level-security role filters a fact a user is writing into, and how that interacts with the shared writeback identity's grants, is undocumented. Raise it in discovery for any module with restricted data.

⚠️ **Multi-user concurrency is structurally tolerated but undefined.** The append-only patterns survive two users editing the same cell; what either user should *see* is not specified anywhere.
