# accoPLANNING — accoTool Custom Visual Configuration

**Status:** in progress — see §9 for what isn't covered yet.

**Confidence markers:**
🟢 Confirmed — verified directly.
🟡 Working baseline — not yet independently verified, or verified once but not across multiple builds.
⚠️ Open — a known gap or unresolved question.

**On the DAX shown below:** a few of accoPLANNING's requirements (§3, §4) can only be described in terms of *which* measure a property must bind to and *what it must be named* — a property of the visual's own write mechanism, not a modeling decision. Every DAX snippet in this file illustrates that requirement's shape only. Authoring, naming for business meaning, and organizing any actual measure is `accotool-ai-semantic-model`'s content, not this file's.

---

## 1. Placing an accoPLANNING visual

**Visual type identifier:** `accoPLANNING_4DAA52ABFBF441E2A7898A79384CAFA9`

🟢 Hand-authored, two-part mechanism (the same shape as accoMASTERDATA's, documented in the `accotool-ai-customvisual-accomasterdata` skill): the type string is registered in `report.json`'s `publicCustomVisuals` array, and a minimal `visual.json` is created with just the type and a position — no `resourcePackages` entry is needed. A freshly-placed instance has no `query` block and no `objects` block until the first field is bound.

🟢 **A freshly placed, unconfigured instance shows its own "How to get started" onboarding screen** (a branded accoPLANNING welcome panel with Step 1 / Step 2 guidance) — not a blank canvas, and not a generic Power BI placeholder. This is the normal, expected state before any data roles are bound. A freshly placed instance showing the generic grey pie/bar/line "Select or drag fields to populate this visual" icon instead is a sign the visual type string itself is wrong (e.g. a typo'd GUID): the visual fails to resolve silently rather than erroring, so this is worth checking before assuming anything else is broken.

---

## 2. Data roles: `Row`, `Column`, `Measure`, `Transaction`, `NonWriteableMeasures`, `Comments`

🟢 **`query.queryState` role keys don't follow a consistent singular/plural pattern** — confirmed so far: `Row`, `Column`, `Measure`, `Transaction` (all singular), but `NonWriteableMeasures` and `Comments` (both plural). The Format-pane field-well labels give no indication of any of this, and the pattern isn't consistent enough to guess a new role's exact key from the others — treat each one as needing its own confirmation rather than assuming a rule.

🟢 **Editability defaults to ON**, the same default accoMASTERDATA uses. Every cell in a tested build rendered as writeable (highlighted, accepting input) with zero explicit `editable` configuration anywhere. Cells do not need to be opted into editability — the property to look for, if it exists, would be one that *restricts* a specific column, not one that enables it (not yet located for accoPLANNING — see §9).

🟢 **A measure's Writeable/Non-writeable classification (set via the Format pane's Measures → Configuration → Measure type dropdown) is a structural role split, not a per-field property.** A measure classified `Writeable` has its projection placed in the ordinary `Measure` role; a measure classified `Non-writeable` has its projection placed in a separate `NonWriteableMeasures` role instead — same projection shape (`Measure`-type, same naming rule as §3), just filed under a different role key entirely. This was not discoverable from the Format-pane schema dump (which only shows a generic `measures.measureType` dropdown with no enum values listed) — it only became clear from reading back a real file after reclassifying measures through the UI. A third classification, `Calculation`, exists in the Format pane (used for a shadow calculation's hidden output measure — see §5) but which role *it* lands in hasn't been observed yet, since the one build this was tested against used `Non-writeable` for that purpose instead (both are valid shadow-calc output types).

### Comment binding

🟢 **A per-cell comment binds through its own role, `Comments`, as a single `Measure`-type projection** — same shape and same naming rule as `Measure`/`Transaction`/`NonWriteableMeasures` (§3): the bound DAX measure's own name has to match the destination text column on the writeback table (e.g. a measure named `Comment` writing to a fact-table column named `Comment`), `nativeQueryRef` has no effect on the write target. No `Transaction`-style key resolution is needed for it — it isn't a dimension.

🟡 Unlike the numeric writeback measures documented elsewhere in this file (which accumulate as delta rows and get summed), the one build this was tested against used a "most recent wins" measure design for the bound comment (reading back the latest value across the accumulated rows for that cell, rather than summing). This is a semantic-model authoring choice, not a requirement accoPLANNING imposes — a different aggregation approach may also work; only "most recent wins" has actually been tested.

### Row and Column: bind display fields, not surrogate keys

🟢 **`Row` and `Column` take one or more plain `Column`-type projections, bound to whatever field should be *displayed*** — a friendly name, a code, a date part. Binding a dimension's raw numeric surrogate key here instead, even when it feels like "the row identity," only changes what's *displayed* (raw IDs instead of readable labels) — it has no effect on writeback, which is resolved through a separate mechanism (§3).

🟢 **Multiple projections in one role build a drill hierarchy**, not a cross-product, by default. Two projections — `Year` then `Month` — under `Column` renders as a two-level column hierarchy (each year expandable to its months); this is the mechanism behind something like a "12 months × N years" grid, not a special multi-column-role feature.

⚠️ A hierarchy built this way can render as a broken linear drill chain (`(blank) → 2026 → 2027 → months`, each year nested under the previous one instead of as siblings) instead of a clean cross-product, under conditions not fully isolated. One contributing factor traced back to a semantic-model-layer column setting (aggregation/summarization behavior — out of this file's scope, see `accotool-ai-semantic-model`), but that may not be the only cause. A genuinely blank/unmatched member (next point) can still appear afterward even once the hierarchy itself renders correctly.

🟢 **A phantom `(Blank)` member can appear in `Row` or `Column` even when the underlying dimension data has no actual blank/null values.** Observed specifically when the dimension is on the "one" side of a relationship to a writeback fact table, "Show items with no data" is enabled for that axis, and the fact table currently has few or no matching rows. The fix is a report-level filter on the field excluding blank, added like any other visual filter — a `filterConfig.filters[]` entry with a `Where` clause `Not(In([the field], [null]))` and `objects.general.isInvertedSelectionMode: true`. In a multi-axis grid, fixing one axis does not fix another axis showing the same artifact — each bound field needs its own copy of the filter. The artifact is independent of the hierarchy-nesting problem above; it can appear whenever "Show items with no data" is on, regardless of whether a hierarchy is involved.

---

## 3. The `Transaction` role — resolving write-back keys for surrogate dimensions

This is the single most important, least discoverable mechanism in accoPLANNING, and the most common source of a failed first build.

🟢 **When a `Row` or `Column` axis displays a friendly field but the destination writeback table stores a surrogate/foreign key (not the displayed value itself), a `Transaction` role projection supplies the actual key value to write.** Without one, the visual attempts the write and fails with something like *"Cannot insert the value NULL into column '\<FKColumn\>'"* — a real INSERT attempt is made, but the key value it tries to send is empty.

🟢 **Transaction projections are `Measure`-type, not `Column`-type.** A `Column`-type projection in `Transaction` behaves as an unwanted extra column-axis grouping field; a measure wrapped in an ordinary aggregation resolves to blank/null. The working shape is a simple, unaggregated DAX measure — typically a `SELECTEDVALUE(...)` against the dimension's own key column:
```dax
FBK_SomeDimension#ID = SELECTEDVALUE(SomeDimension[BK_SomeDimension#ID])
```
This resolves correctly because the visual's own Row/Column filter context (from whatever *display* field is bound in Row/Column) already narrows the dimension to exactly one row when a specific cell is being written — the measure only needs to read the key off that one row.

🟢 **Only dimensions whose destination column is a surrogate/FK key need a `Transaction` entry.** A dimension where the fact table already stores the *literal displayed value itself* (e.g. a plan year or month stored as a plain integer, not a lookup key) needs no `Transaction` entry — it writes correctly bound directly in `Row`/`Column` as in §2. Which dimensions need one varies per module: a given build might need one for every axis, one for none, or something in between, depending on whether each axis's underlying fact-table column is a lookup key or a literal value.

### The critical, easy-to-miss naming rule

🟢 **For `Measure`-type projections (in both `Measure` and `Transaction`), accoPLANNING infers the destination column name from the bound DAX measure's own name — not from `nativeQueryRef`.** This is the opposite of how a plain `Column`-type projection's write target is named:

| Projection type | What governs the destination column name |
|---|---|
| `Column`-type (used in `Row`/`Column` for a directly-written field) | `nativeQueryRef` — the field's display label can be renamed freely without affecting where it writes |
| `Measure`-type (used in `Measure` and `Transaction`) | **The measure's own name.** `nativeQueryRef` has no effect on the write target for a measure-type projection — the write keeps targeting a column named after the measure itself |

**Practical implication:** if a fact table column is `PlannedAmount` and the bound DAX measure is named `Planned Amount` (or anything else), the measure itself needs to be renamed to `PlannedAmount` — setting `nativeQueryRef: "PlannedAmount"` on the projection alone has no effect on the write target. This was verified directly: reproducing the failure (renaming only `nativeQueryRef`, write still failing with the same error) and then resolving it (renaming the underlying measure, write succeeding immediately, same visual, same session, no other change).

### Worked example (illustrative shape, not a fixed recipe)

A module with a `Row` axis showing an account name (backed by a surrogate key) and a `Column` axis showing year/month (stored literally on the fact table):
- `Row`: one `Column`-type projection → the account's display-name field.
- `Column`: two `Column`-type projections → year field, then month field (hierarchy).
- `Measure`: one `Measure`-type projection → a DAX measure named exactly after the fact table's amount column.
- `Transaction`: one `Measure`-type projection → a `SELECTEDVALUE`-based DAX measure, named exactly after the fact table's FK column, resolving the account's surrogate key.

A module with more writeback dimensions needs one `Transaction` entry per surrogate-keyed dimension — the pattern repeats rather than changing shape.

---

## 4. Connection & credential binding

Object group: **`planningConnection`**. Property names are entirely different from accoMASTERDATA's `connection` group; nothing about that visual's binding pattern carries over automatically.

🟢 **Confirmed property names**, bound to measures the same way accoMASTERDATA binds its own credential properties (never as literals, except where noted). The "binds to" column states *which* measure each property needs — the measures themselves (their DAX, the `Config_Connection`/`Config_Writeback`-style bridge they read from) are `accotool-ai-semantic-model`'s content:

| Property | Purpose | Binds to |
|---|---|---|
| `writebackTarget` | Target type | Literal `'SQL'` |
| `isFabric` | Whether writing to a Fabric Warehouse | Literal `false` |
| `host` | Server name | Measure (server bridge) |
| `DB` | Database name | Measure (database bridge) |
| `user` | Database user | Measure (user bridge) |
| `password` | Database password | Measure (password bridge) |
| `schemaName` | Writeback table's schema | Measure (per-module schema bridge) |
| `writeBack` | Writeback table name | Measure (per-module table bridge) |
| `currentUser` | Current user stamp | Measure (current-user bridge) |
| `usernameColumn` | Column on the writeback table that logs the editing user | Literal — the visual's own default is very unlikely to match a real column name and needs overriding |
| `timestampColumn` | Column on the writeback table that logs the edit timestamp | Literal — same, the default needs overriding |
| `batchRows` | Whether same-cell edits to multiple bound fields combine into one written row — see below | Literal `true`/`false` |

🟢 `writebackTarget`/`isFabric` (and other Format-pane defaults) get auto-populated into the file the first time the visual's own onboarding flow is interacted with in Desktop — they can already be present before anything has been bound intentionally.

🟢 **`batchRows` (Format-pane label "Batch changes by row") defaults to `false`, and that default means editing more than one bound field on the same cell in a single save produces one written row *per edited field*, not one combined row.** Confirmed directly: editing `Quantity` and `Comment` together on the same account/period cell and saving produced two separate rows in the writeback table — one with the new `Quantity` and `Comment` left `NULL`, the other with the new `Comment` and `Quantity` left `NULL`. Setting `batchRows: true` on `planningConnection` fixed this immediately — the same edit then produced a single row with both values populated. This isn't necessarily wrong behavior with the default off (a module might genuinely want one row per field edit), but it's very likely not what's expected by default, and it's easy to build a module, see split rows, and assume something is broken rather than realize this is a configuration switch.

🟢 **No separate audit-log table/object group like accoMASTERDATA's `auditLogEnabled`/`auditLogSchema`/`auditLogTable`/etc.** `usernameColumn`/`timestampColumn` on `planningConnection` are the entire audit surface, and they stamp columns directly on the **same writeback table** the data itself lands on — confirmed from a real successful write, where `UpdatedBy`/`UpdateDateTime` appeared correctly populated on the same fact-table row as the written value, with no separate audit table involved. There is no toggle to disable this stamping; it's core to every write.

🟡 `authenticationMethod` — absent (never set) in the one build this was tested against, and writeback worked correctly without it. Whether explicitly setting it causes the same "silently reverts to onboarding" failure documented for accoMASTERDATA is unconfirmed either way.

🟢 **A Desktop save reverts the automated-credential state, the same as accoMASTERDATA.** `user`/`password` get rewritten to the literal `'********'` and `encryptedUser`/`encryptedPassword` get freshly regenerated — confirmed directly, more than once, across saves triggered by both report-level saves and an in-grid cell edit/write. (An earlier version of this note claimed the opposite, based on a build that happened not to have hit a save yet at the time — that was wrong, not a real contrast with accoMASTERDATA.) The fix is the same pattern each time: delete `encryptedUser`/`encryptedPassword` entirely, rebind `user`/`password` back to their measures, then reload (not save). Check this immediately after any Desktop save, before assuming writeback still works.

---

## 5. Shadow calculations — the only calculation type that writes back

accoPLANNING has three distinct calculation mechanisms; only one of them persists its result. Per accoPLANNING's own documentation: **Shadow Calculations** write their result to the SQL writeback table (and can optionally save it as a delta from the prior value — see below); **Cell Calculations/Splashing** (typed directly into a cell, e.g. `10+5`) and **Custom Calculations** (broader syntax, sibling-dimension/measure references) are both display-only and never write back. If a calculated value needs to persist, it has to be a Shadow Calculation — nothing else in this list is a substitute.

🟢 **Prerequisite: the measures involved need to already be classified per §2.** The shadow calculation's *output* measure must be classified `Non-writeable` or `Calculation` (never `Writeable` — confirmed both by the Advanced Options UI itself refusing a Writeable measure as output, and by using `Non-writeable` successfully as the output type in a tested build). Input measures referenced in the formula can be any classification.

🟢 **The calculation itself is built through Desktop's Advanced Options panel** (the toolbox icon in the visual's own toolbar, or three-dot menu → Edit), under Calculations → Shadow calculations — not through the ordinary Format pane. Pick the output measure, write the formula referencing other bound measures in square brackets (e.g. `[PlannedAmount] = [Quantity] * [Unit Cost]`), and there's a "Calculate delta for shadow calculations" checkbox alongside it.

🟢 **Storage: a new object group, `objects.calculations`, holding one property (`calculations`) whose value is a single literal string containing every shadow calculation for the visual** — not one property per calculation. The observed shape, semicolon-delimited: a leading empty segment, then one segment per calculation formatted roughly as `[OutputMeasure] = [Formula]¿<word>` (a `¿` character separating the formula from a trailing token seen as `false` in every case observed here — its meaning is unconfirmed, see §9).

🟡 **Hand-editing this string directly is confirmed safe for removing or trimming an existing entry** — done directly in a real build (editing the literal string, then reload) without breaking the remaining calculation, which kept computing correctly afterward. Whether hand-*authoring* a brand-new calculation from scratch (rather than editing what the UI already wrote) would also work is unverified — every calculation seen in a real file so far originated from the Advanced Options UI, not from hand-authoring.

🟢 **Deleting a shadow calculation** (general procedure, useful whenever an existing calculation turns out to be redundant or wrong, not a routine step): Advanced Options → Calculations → Shadow calculations → Calculation overview lists every existing calculation with edit (pencil) and delete (trash) icons next to it; deleting one there and saving removes its segment from the stored string. Hand-editing the string directly (previous point) is the alternative when working from files rather than the UI.

🟢 **The delta checkbox works as documented, confirmed against live writeback data**, and stays mathematically consistent across multiple accumulated writes even when individual rows look inconsistent in isolation. Concrete example from a real build: three accumulated rows for the same account/period had `Quantity` values of *(blank)*, `10`, `-7` and `PlannedAmount` values of `66`, `934`, `-700` — summed, `Quantity` totals `3` and `PlannedAmount` totals `300`, matching `3 × UnitCost(100) = 300` exactly. The `934` row is not an error: it's the delta needed to bring the running total from the prior `66` up to the new target of `1,000` (`10 × 100`), which is exactly what "Calculate delta" is supposed to produce.

🟢 **Recalculation is trigger-based, the same as accoMASTERDATA's shadow calculations**: a shadow calculation recomputes only when triggered by an edit to some other field on the row, not continuously or on report load. See §9 for an open case where a triggering edit was written to SQL but didn't produce a matching recalculation until a later edit.

---

## 6. Reload / Desktop mechanics

🟢 No accoPLANNING-specific differences found from the generic mechanics documented in the `accotool-ai-customvisual-accomasterdata` skill: a `reload` (not a Desktop UI save) is what picks up a hand-authored file edit, and a reload error does not always mean the reload actually failed.

🟢 One thing specific enough to this visual's build history to restate here: **a hand-edited file not yet picked up by a `reload` can be silently overwritten by the next Desktop *save*** — Desktop writes its own in-memory copy back to disk, and that in-memory copy never had the file edit. When a save is needed for an unrelated reason (e.g. persisting a live semantic-model change made through a modeling tool), doing that save *before* making the file edit — not after — avoids losing the edit.

---

## 7. Grand Total / Hierarchy defaults

🟡 A row/column labeled "Hierarchy" header and an automatic "Grand Total" row and column appear by default with no configuration. How to rename, relabel, or disable these is not yet explored.

---

## 8. Why this is hand-authored rather than CLI-driven

🟢 accoPLANNING is a proprietary `.pbiviz` outside Microsoft's catalog — `powerbi-report-author catalog describe accoPLANNING_...` returns `VISUAL_TYPE_UNKNOWN`, confirmed directly. No CLI fallback exists for it; every fact in this file comes from direct testing or from reading a real working file, never from CLI introspection. (accoMASTERDATA is in the same position, for the same reason.)

---

## 9. Not yet covered — do not assume or guess ahead of building it

- Whether other `Writeback → Settings` properties in the same family as `batchRows` (e.g. `sendOnlyKeys`, `batchChanges`) have similarly significant, easy-to-miss effects on how/when writes land — only `batchRows` has been deliberately tested so far (§4).
- The exact meaning of the trailing `¿<word>` token in each shadow-calculation string segment (§5) — every case observed so far reads `¿false`; what it represents and whether/when it might read `true` is unconfirmed.
- Whether hand-authoring a brand-new shadow calculation from scratch (rather than editing/trimming one the Advanced Options UI already wrote) works — only editing an existing, UI-authored entry has been verified (§5).
- A case where a `Quantity` edit was written to SQL but its shadow-calculation recalculation of `PlannedAmount` didn't happen until a later, separate edit (§5) — the recalculation trigger isn't fully understood; the accumulating-delta model self-corrected the running total once the later edit did trigger, but the root cause of the missed trigger is unknown.
- Which role a `Calculation`-classified measure's projection lands in (§2) — only `Non-writeable` has been used as a shadow-calc output type so far, and `Calculation` is documented as an equally-valid alternative that hasn't been tried.
- A pair of fields seen in other accoPLANNING builds' `Row`/`Column` projections, sourced from an entity literally named `Total` (e.g. `Total.Row Total` / `Total.Column Total`) — present in every external reference example inspected while building this file, absent from the one working build documented here (which functioned correctly without them). Whether they're required for some not-yet-exercised capability (e.g. custom subtotal placement/behavior) or incidental to how those other reports happened to be built is unknown.
- Dropdown cells, cell locking, splashing (distributing a value across a range), min/max validation, and general grid/layout styling — all present as configurable surface in the Format-pane schema, none exercised yet in a real build.
- Named style presets (accoMASTERDATA has an equivalent open item) — not investigated for accoPLANNING specifically.
- Which property restricts editability on a specific column (§2 notes the default is ON; the restricting property itself hasn't been located).

Each of these gets added to this file once it's actually built and verified.
