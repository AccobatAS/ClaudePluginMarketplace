# accoTOOL Cross-Layer Contracts & Symptom Router

Every other accoTOOL skill owns exactly one layer of the writeback chain, and each is deliberately scoped so that none of them owns the whole. That scoping is correct, but it leaves a category of fact with no home: the **invariants that only exist between two layers**. A name that must match across a schema, a model and a visual isn't a database fact, a modeling fact, or a visual fact — it is a contract, and a contract nobody owns is a contract nobody checks.

This file is that owner. It states the contracts and nothing else: no DDL, no DAX, no property tables. Each contract names the skills and sections that own its two ends — go there for the detail.

**Read this when:** wiring a module end to end, handing a build from one layer to the next, or debugging a failure whose symptom appears in a different layer from its cause (which is most of them — see the symptom router at the end).

**Confidence markers** — same convention as every other accoTOOL reference:
🟢 Confirmed · 🟡 Working baseline · ⚠️ Open

---

## C1 — A datamart view's name *is* the model table's name

🟢 `accotool-ai-sql-schema` §9 names datamart views so that no translation is ever needed downstream: `_{Name}` for facts, `{Name}` for dimensions, `Config_{Name}` for metadata. `accotool-ai-semantic-model` §1 loads each one under that exact name.

**The contract:** a mismatch is upstream drift, not a modeling decision. Fix it at the datamart, never by renaming the model table to paper over it.

---

## C2 — The datamart view's *type* decides the model table's storage mode

🟢 Writeback fact view → DirectQuery. Reference/dimension view → **Dual**. Config/metadata view → Import. (`accotool-ai-semantic-model` §2.)

**The contract:** an Import dimension related to a DirectQuery fact produces a weak relationship that silently breaks filter propagation. Dimensions are Dual *because* the fact is DirectQuery — the two decisions are one decision, not two.

---

## C3 — In Pattern B, the visual writes to a different table than the model reads

🟢 `accotool-ai-sql-schema` §6.2: accoPLANNING writes into `Fact_{Name}_RAW#AP`; an `AFTER INSERT` trigger merges into `Fact_{Name}_Current`; the datamart fact view `_{Name}` reads *Current*. Current is explicitly **not** a writeback target.

**The contract, in three parts:**
- `Config_Writeback.TableName` (§4.2) must name the **RAW** table — that row is what the connection measures resolve into the visual's write target.
- The model table (C1) is the datamart view over **Current**.
- Because the fact is DirectQuery (C2), the trigger's output is visible to the report the moment the write commits — that is the mechanism by which the loop closes on the page (see [`accotool-ai-page-composition.md`](accotool-ai-page-composition.md)).

Pattern A (accoMASTERDATA) and simple append-only Pattern B have no such split: write target and read source are the same table behind the view.

---

## C4 — Which name governs the write target differs *per visual*. Never carry one over

This is the highest-frequency cross-layer failure in the whole set, and the two visuals genuinely disagree:

| Visual | Projection type | What names the destination column | Owner |
|---|---|---|---|
| accoPLANNING | `Measure`-type (roles `Measure`, `Transaction`, `NonWriteableMeasures`, `Comments`) | 🟢 **the bound DAX measure's own name.** `nativeQueryRef` has no effect | `accotool-ai-customvisual-accoplanning` §3 |
| accoPLANNING | `Column`-type (roles `Row`, `Column`) | 🟢 `nativeQueryRef` — the display label can be renamed freely | same, §2–§3 |
| accoMASTERDATA | any renamed field | 🟢 an explicit entry in `objects.connection[]` pointing writeback at the real column | `accotool-ai-customvisual-accomasterdata` §4 |

**The contract:** the SQL column name (`accotool-ai-sql-schema` §3) is fixed first; whichever mechanism above applies then has to be made to match *it*. For accoPLANNING this reaches back into `accotool-ai-semantic-model` — the measure itself must be renamed, which is why §9 there treats measure naming as load-bearing rather than cosmetic, and why a measure may have to be hosted on a table that doesn't carry a colliding column.

---

## C5 — The connection bridge is a five-hop chain, and every hop must resolve to exactly one row

🟢 The chain, end to end:

```
accoTOOL$Base.Config_Connection / Config_Writeback   accotool-ai-sql-schema §4.1 / §4.2
  -> datamart Config_ views                          accotool-ai-sql-schema §9
  -> Import model tables                             accotool-ai-semantic-model §2
  -> measures on the dedicated _Measures table       accotool-ai-semantic-model §6, §8
  -> the visual's credential properties              AM §5 (connection) / AP §4 (planningConnection)
```

**Contract part 1 — measure-bound, never literal.** Every credential/connection property binds to a measure, with only the per-visual literal exceptions each visual's own skill calls out. AM's group and AP's group use *different property names for the same concepts*; neither may be inferred from the other.

**Contract part 2 — the filter must be narrow enough to return one row.** `CALCULATE(SELECTEDVALUE(…), …)` returns `BLANK` the instant its filter matches two rows, and a blank credential is a writeback failure with no visible error. `Config_Connection` holds one row by design, but `Config_Writeback` holds **one row per writeback table** — so a module with both an accoMASTERDATA dimension and an accoPLANNING fact has two rows sharing a `ModuleName`. A schema/table measure filtered on `ModuleName` alone silently breaks the moment the second table is registered. Filter on `VisualCode` as well (and on `TableName` where one module has several tables of the same visual type). See `accotool-ai-semantic-model` §6.

**Contract part 3 — a Desktop save undoes it.** 🟢 Confirmed for both visuals: a save rewrites `user`/`password` to literals and regenerates the encrypted blobs. Re-check after *every* save, not once at setup (AM §5, AP §4).

---

## C6 — Who stamps the user and the timestamp, and where

The two visuals solve this completely differently, and the database side has to match whichever one is in play:

| Visual | Mechanism | Database side |
|---|---|---|
| accoMASTERDATA | 🟢 audit-block properties in the `connection` group, pointing at a separate audit table (AM §6) | the single shared `accoTOOL$Base.Log_Audit` — exactly five framework columns plus `LogKey` (`accotool-ai-sql-schema` §4.3) |
| accoPLANNING | 🟢 `usernameColumn` / `timestampColumn` on `planningConnection`, stamping the **same** row the value lands on; no audit table exists (AP §4) | the mandatory `UpdatedBy` / `UpdateDateTime` columns every fact already carries (`accotool-ai-sql-schema` §3) |

**The contract:** accoPLANNING's two properties are literals whose visual defaults are very unlikely to match a real column, so they must be overridden — and in this framework the values they must be overridden *to* are `UpdatedBy` and `UpdateDateTime`. There is no toggle to disable the stamping.

⚠️ The corollary that keeps getting re-litigated: `Log_Audit` must not gain differentiator columns (`ModuleName`/`SchemaName`/`TableName`) to identify which module a shared audit row came from — accoMASTERDATA has no property able to populate arbitrary extra `NOT NULL` columns, so every write would fail the constraint. The cross-module identification problem is genuinely unsolved (`accotool-ai-sql-schema` §13); don't "fix" it by adding columns the visual cannot fill.

---

## C7 — The visual code is one fact written in three places

🟢 `AM` / `AP` / `AC` appears as the table-name suffix (`Dim_Employee#AM`, `Fact_SalaryPlan#AP`), as `Config_Writeback.VisualCode`, and as the choice of which skill configures the visual. All three must agree. A table suffixed `#AP` registered with `VisualCode = 'AM'` is a build error even though every individual object is valid.

Reminder on quoting: `#` in any object name must always be bracket-quoted in SQL — `[Fact_Name#AP]`.

---

## C8 — Delta writes and the merge aggregation are one decision, made in two skills

🟢 accoPLANNING can write **deltas** rather than absolute values — confirmed in `accotool-ai-customvisual-accoplanning` §5, where three accumulated rows for one cell read *(blank)* / `10` / `-7` and only *sum* to the correct current value.

🟢 `accotool-ai-sql-schema` §6.2's RAW→Current trigger exists precisely so downstream never has to do that summing itself.

**The contract:** the merge's aggregation must match the write mode the visual is configured for. Deltas require `SUM`; absolute writes require *latest non-null by `UpdateDateTime`*. Neither is a default to assume — check the visual's shadow-calculation delta setting (AP §5) before writing the trigger, and re-check the trigger if that setting later changes. Getting this wrong produces a table full of plausible numbers that are quietly wrong, with no error anywhere.

---

## C9 — Any measure a visual property binds to lives on `_Measures`

🟢 `accotool-ai-semantic-model` §8: a measure hosted on a data table made the consuming property vanish entirely from the visual's Format pane; the identical measure moved to the dedicated table worked immediately. `Measures` is a reserved table name — use `_Measures`.

**The contract:** this covers the connection bridge, `Transaction`-role key measures, dropdown-feeding measures, and comment measures alike. What the measure *reads* is unconstrained; only where it is *hosted* matters.

⚠️ The exact string shape such a measure must return (delimiters, key-before-label ordering) is dictated by the consuming visual property, not by the model — AM §10 confirms `"key;label|key;label"`, stored value first. Reversing it drives the visual wrong without erroring.

---

## Symptom router

A failure in this architecture almost never surfaces in the layer that caused it. Find the symptom, go to the owner — don't debug outward from where it appeared.

| Symptom | Layer that actually owns it | Where |
|---|---|---|
| `Cannot insert the value NULL into column '<FK>'` on a write | accoPLANNING — missing `Transaction` projection for a surrogate-keyed axis | AP §3 |
| Writes stopped working after a Desktop save; no error | either visual — credential state reverted | AM §5 · AP §4 · C5 |
| A connection/schema/table measure returns blank | semantic model — filter matches more than one row | semantic-model §6 · C5 |
| A property disappeared from the visual's Format pane | semantic model — measure hosted on a data table, not `_Measures` | semantic-model §8 · C9 |
| One written row per edited field instead of one combined row | accoPLANNING — `batchRows` defaults to `false` | AP §4 |
| A value written to the right cell lands in the wrong column | naming mechanism differs per visual | C4 · AP §3 · AM §4 |
| A calculated value renders but never persists | accoPLANNING — only shadow calculations write back | AP §5 |
| Numbers in `_Current` are plausible but wrong after repeated edits | SQL — merge aggregation doesn't match the visual's delta mode | C8 · sql-schema §6.2 |
| A phantom `(Blank)` member on a Row or Column axis | accoPLANNING — "show items with no data" against a sparse fact | AP §2 |
| A hierarchy renders as a broken linear drill chain | accoPLANNING, with a contributing cause in the model's column summarization | AP §2 · semantic-model |
| Filter propagation silently doesn't reach the fact | semantic model — Import dimension against a DirectQuery fact | semantic-model §2 · C2 |
| A newly added column is invisible past the base table | SQL — every view uses explicit column lists, never `SELECT *` | sql-schema §10.2 |
| The visual renders the generic grey field placeholder instead of its own onboarding screen | the visual type GUID is wrong; it fails to resolve silently | AP §1 · AM §1 |
| A hand-authored file edit vanished | Desktop's save wrote its in-memory copy over it — save *before* editing, then reload | AP §6 |
| The live model is empty (0 tables) after a `reload` | semantic model — `reload` does not restore the model side of a PBIP | semantic-model §11 |
| Desktop crashed on a push right after a reload | semantic model — stale Mashup session | semantic-model §11 |
| `The key didn't match any rows in the table` in Power Query Editor | semantic model — benign editor-preview limitation on Dual/DirectQuery tables | semantic-model §11 |
| An audit insert fails a `NOT NULL` constraint | SQL — extra columns the visual cannot populate | sql-schema §4.3 · §13 · C6 |
| Two Desktop windows disagree about which is "the" instance | environment — both are real, each with its own AS port | semantic-model §11 |
| The write works, the page doesn't show it | page composition — which visuals see a write, and when | [`accotool-ai-page-composition.md`](accotool-ai-page-composition.md) |
