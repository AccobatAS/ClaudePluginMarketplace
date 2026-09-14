# accoTool Semantic Model — Modeling Reference

The per-topic modeling detail for `accotool-ai-semantic-model`: table loading, storage modes, relationships,
partitions, date tables, the connection-measure bridge, writable-measure patterns, measure organization,
naming constraints, and model-view layout.

SKILL.md holds the scope, the build order, and §11 (known environment gotchas) — read it first.
Section numbers here match the numbering SKILL.md points at; **§11 lives in SKILL.md, not in this file**,
because those gotchas are operationally dangerous to be missing.

**Confidence markers** (same convention as SKILL.md):
🟢 Confirmed — verified against a real, currently-deployed build.
🟡 Working baseline — adopted, pending independent confirmation.
⚠️ Open — a known gap or unresolved question.

---

## 1. Table Loading & Naming

🟢 Load each accoTool datamart view (`accotool-ai-sql-schema` §9) as a model table with the **exact same name as the view**. This isn't a separate naming decision to make here — it's already guaranteed by that skill's naming convention (`_{Name}` for facts, `{Name}` for dimensions, `Config_{Name}` for metadata), which exists specifically so a datamart view's name never needs translating when it becomes a model table. If a table name in the model doesn't match its source view name exactly, something drifted upstream — that's a bug to trace back to the datamart, not something to reconcile here.

Use `table_operations` (`Create`, pointing `entityName`/`schemaName` at the datamart view) to bring each view in — one call per table, or batched via the `definitions` list.

---

## 2. Storage Mode Assignment

🟢 Confirmed pattern, keyed to the datamart view type (`accotool-ai-sql-schema` §9):

| Datamart view type | Storage mode | Why |
|---|---|---|
| Writeback fact view (`_{Name}`, backed by `Fact_{Name}_Current` or `Fact_{Name}#AP`) | DirectQuery | Writeback must read current state live — no refresh lag |
| Reference/dimension view (`{Name}`, backed by `vw_Dim_{Name}`) | Dual | Lets the engine choose Import or DirectQuery per query, rather than forcing every join through DirectQuery |
| Config/metadata view (`Config_Connection`, `Config_Writeback`) | Import | Small, rarely-changing, has no writeback dependency of its own |

⚠️ **Never pair an Import dimension with a DirectQuery fact** — creates a weak/limited relationship (visible as a half-circle join in the model view diagram), which silently breaks filter propagation between the two tables. If a dimension must relate to a DirectQuery fact, it needs to be Dual, not Import.

---

## 3. Relationships

🟡 Standard star-schema shape: one relationship per dimension-to-fact pair, single-direction filtering (dimension filters fact, not the reverse), joined on whatever key column the datamart views actually expose (`accotool-ai-sql-schema` §9's dimension/fact view templates pass `BK_{Name}#ID`/`FBK_{Dim}#ID` through unchanged — check the actual view's column list rather than assuming a renamed alias). Respect the storage-mode compatibility rule in §2 — never relate an Import dimension to a DirectQuery fact.

Use `relationship_operations` (`Create`) with `fromTable`/`fromColumn` on the dimension side, `toTable`/`toColumn` on the fact side, `fromCardinality: "One"`, `toCardinality: "Many"`.

---

## 4. Partition / M Pattern

🟢 **Inline `Sql.Database(...)` in every partition's M query. Do not use a shared named expression** (e.g. one `AccoToolDataSource` expression referenced by every table's partition). A parameterized `Server`/`Database` plus a shared expression caused `The name 'Server' doesn't exist in the current context` on every PBIP open — Desktop cannot resolve multi-level shared-expression references when restoring the Mashup document from TMDL. This cost a full debugging cycle to diagnose the first time; treat it as settled, not a style preference to reconsider.

⚠️ `database.tmdl`'s database name gets clobbered (rewritten to the workspace GUID) on every `powerbi-modeling-mcp` `ExportToTmdlFolder` call, and Desktop's own save has separately been seen to strip `compatibilityMode`/`language` from the same file. Check and fix this file after every export — don't assume it survived the round-trip unchanged.

---

## 5. Date Table Sourcing

🟡 Whether a `Date` table needs building from scratch depends on whether the target database uses **accoOneDB** — the organization's own standard data-warehouse product.

**Detection:** check for a `Dim_Date` table inside a `DW` schema, *and* a stored procedure that references or populates it. Both signals together indicate accoOneDB is in play. Either signal alone is not sufficient — if only one is present, ask rather than guess.

- **accoOneDB present:** import that `Dim_Date` table directly as the model's `Date` table (do not build a separate one), then mark it as the official date table:
  ```
  table_operations → operation: MarkAsDateTable
  markAsDateTableDefinitions: [{ tableName: "Date", dateColumnName: <omit to auto-detect> }]
  ```
- **accoOneDB absent:** either build a `Date` table from scratch (a calculated table via `CALENDAR()`/`CALENDARAUTO()`, or via `calendar_operations` if the model's compatibility level supports the newer Calendar object — check that tool's `Help` operation for the minimum compatibility level first) or use Power BI's own built-in auto date/time tables, whichever the discovery conversation calls for. This is a per-build decision, not a default — don't assume either path without confirming.

---

## 6. The Connection-Measure Bridge

🟢 **Never hardcode connection values into measure DAX.** The entire point of `Config_Connection`/`Config_Writeback` (owned by `accotool-ai-sql-schema` §4.1/§4.2) is that credentials and writeback targets live in the database, not in the model. This layer's only job is exposing them as measures the visuals can bind to.

`Config_Connection` is designed to hold a single shared row under the current standard (`accotool-ai-sql-schema` §4.1), but **every measure reading it must still filter explicitly rather than relying on that.** Never use bare `SELECTEDVALUE` — it silently returns `BLANK` the moment a second row ever exists, which is a writeback failure with no visible error:

```
Connection Server = CALCULATE(SELECTEDVALUE(Config_Connection[ServerName]), Config_Connection[DBUser] = "writeback_user")
```

Standard measure set, all following the same `CALCULATE(SELECTEDVALUE(...), filter)` shape — these belong in the `Connection` measure-folder (§7):

- `Connection Server`, `Connection Database`, `Connection User`, `Connection Password` — filtered on `Config_Connection[DBUser]`
- `Connection CurrentUser` = `USERPRINCIPALNAME()` — the one exception; not a `Config_Connection` lookup at all
- `Connection Schema {AM|AP}`, `Connection Table {AM|AP}` — one pair per module/visual combination present in the report

⚠️ **The `Config_Writeback` pair must filter on `VisualCode`, not on `ModuleName` alone.** `Config_Connection` holds one row for the whole database by design, but `Config_Writeback` holds **one row per writeback table** (`accotool-ai-sql-schema` §4.2) — so a module with an accoMASTERDATA dimension *and* an accoPLANNING fact has two rows sharing a `ModuleName`, and a `ModuleName`-only filter hits the exact multi-row `BLANK` failure this section opens by warning about. It fails silently, and it fails the moment the module's second writeback table is registered — not when the measure is written, which is what makes it easy to ship:

```
Connection Table AP =
    CALCULATE(
        SELECTEDVALUE(Config_Writeback[TableName]),
        Config_Writeback[ModuleName] = "{ModuleName}",
        Config_Writeback[VisualCode] = "AP"
    )
```

Where one module has several tables of the *same* visual type, `VisualCode` is not enough either — add `TableName` (or whatever else distinguishes them) until the filter provably returns one row. Verify with a DAX query rather than assuming: a measure returning a plausible-looking value for the module you happen to be testing can still be one `INSERT` into `Config_Writeback` away from returning blank.

🟢 The value these two measures must resolve to is the **writeback target**, which in Pattern B is the `Fact_{Name}_RAW#AP` table — not the `Fact_{Name}_Current` table and not the datamart view this model loads as a table. The visual writes to RAW; the model reads Current through the datamart view; a trigger connects them (`accotool-ai-sql-schema` §6.2). The two names are deliberately different objects, and `Config_Writeback` names the first one.

🟢 **This pattern is confirmed working for every field, including the password** — validated via live writeback on both accoMASTERDATA and accoPLANNING, with no password ever typed manually. See the consuming visual's own skill for exactly which property each of these measures binds to, and which UI-entry artifacts (encrypted blobs) to delete once a measure binding replaces them: `accotool-ai-customvisual-accomasterdata` §5 for accoMASTERDATA's `connection` group, `accotool-ai-customvisual-accoplanning` §4 for accoPLANNING's `planningConnection` group. The two use different property names for the same concepts and must not be inferred from each other — that mapping is product-specific and deliberately not repeated here.

⚠️ **Production security caveat:** exposing `DBPassword` this way puts the plaintext credential inside the semantic model itself — anyone who can open the model can read it. Accepted for PoC/demo with a least-privilege writeback identity (`accotool-ai-sql-schema` §4.1); a deliberate call to revisit before production, not an oversight.

---

## 7. Writable Measure Patterns

🟡 Working baseline from a real accoMASTERDATA build outside this project — not yet independently tested here.

Beyond the connection bridge (§6), a writable measure bound to an accoPLANNING/accoMASTERDATA field isn't limited to mirroring one column 1:1 — it can embed real logic to decide what value to expose or derive.

**Conditional derivation based on a sibling field's current value** — a writable measure can `SWITCH` on the currently-stored value of another field to decide which source to pull from, rather than always reading the same column:

```
Estimate Output =
    VAR _EstimateFunction = SELECTEDVALUE(<WritebackTable>[Type])
    RETURN
        SWITCH(TRUE(),
            _EstimateFunction = "Run Rate", SUM(<ReferenceTable>[Run Rate]),
            _EstimateFunction = "LTM",      SUM(<ReferenceTable>[LTM]),
            _EstimateFunction = "Manual",   SUM(<WritebackTable>[Amount])
        )
```

This lets one writable field's displayed (and subsequently written-back) value come from a different source depending on a mode the user selects elsewhere in the same row — useful when a business case needs a manual-entry option alongside one or more calculated/derived options, without needing a separate writeback column per mode.

**Seeding a sensible default for a never-written row** — `SELECTEDVALUE`'s second argument supplies a default when no row exists yet, instead of showing blank:

```
Estimate Function = SELECTEDVALUE(<WritebackTable>[Type], "Manual")
```

Pair this with the visual-side default-on-create properties (`accotool-ai-customvisual-accomasterdata`'s territory — its `measures` object group carries `defaultValueOnCreateEnabled` and the per-type default values) so a brand-new row's dropdown/toggle state and its measure-computed display value agree from the first render.

---

## 8. Measure Organization

🟡 All measures live in a single dedicated measures table — not scattered across the data tables they reference — organized into `displayFolder` subfolders **by concern**:

- A `Connection` subfolder holding the standard connection-measure set from §6
- One subfolder per business module, named after the module (matching `Config_Writeback.ModuleName`), holding that module's own business measures

Use `measure_operations` `Create` with `tableName` set to the dedicated measures table and `displayFolder` set to `"Connection"` or the module name; use `Move` to relocate a measure between tables/folders without recreating it (`Update` cannot change table assignment).

⚠️ The dedicated measures table itself has to exist before measures can be created against it — typically a small placeholder table, since Power BI requires every measure to belong to *some* table. Creating that placeholder is mostly generic TMDL mechanics (defer to the Microsoft plugin for the general case), but the following specifics are project-confirmed and easy to get wrong:

🟢 **`Measures` is a reserved name — cannot be used as a table name.** Use `_Measures` (or another non-reserved name) instead. Attempting to create a table literally named `Measures` fails outright.

🟢 **No table, calculated or M-sourced, can ever have zero columns — this is a hard tabular-engine constraint, not a tooling limitation.** A DAX-calculated table's column can never be deleted directly (`"Calculated table columns are derived from the DAX expression. Modify the DAX expression directly..."`), and even an M-sourced table refuses to drop its last remaining column (`"Non-calculated tables must have at least one column defined."`) — confirmed by hitting both errors directly. The achievable target is exactly one column, hidden — not zero columns, regardless of what generic online guidance about "dedicated measure tables" might suggest.

🟢 **The Fields-pane "measure table" icon (calculator stack) can lag behind the real model state when changes are pushed through an external connection (this MCP) rather than Desktop's own UI.** Hiding the placeholder column is sufficient at the model level, but Desktop's Fields pane may keep showing the plain-table icon until: (a) the column's calculation state is no longer `CalculationNeeded` — trigger a `table_operations` `Refresh` with `refreshType: "Calculate"` if it is — and (b) in some cases, the PBIP is fully closed and reopened rather than just glanced at, since the pane doesn't always re-evaluate icon logic on its own after an externally-pushed change. Don't conclude the model is misconfigured just because the icon looks wrong; verify the column's actual `isHidden`/`state` first.

🟢 **The dedicated measures table is deliberately zero-row, not just single-column.** Confirmed from Desktop's own M formula for it: `let Source = #table({"Column1"}, {}) in Source` — one column definition, an empty row list. This is why a *calculated column* added to this table can never hold a value (`COUNTROWS` on it returns blank; there's no row for a column to populate) even after a full refresh — it's not a refresh-timing issue, the table has nothing to compute into. Measures work fine here regardless, since a measure doesn't need row data on its own host table to evaluate. Don't try to fix an "empty calculated column" on this table by refreshing harder — the fix is not adding a calculated column here at all.

🟢 **This table isn't only for the connection bridge (§6) — any measure a visual property binds to belongs here too, including one built to feed a dynamically-generated list (e.g. a dropdown).** Confirmed against accoMASTERDATA (`accotool-ai-customvisual-accomasterdata` §10): a measure created directly on a data table (to feed a visual's dropdown-list property with a live, changing set of values) made the consuming property's configuration disappear entirely from the visual's Format pane; the identical measure, moved to this dedicated table, worked immediately. The measure's own DAX can still aggregate over that data table — only where it's *hosted* matters, not what it reads:

```
Manager Dropdown KeyValue =
    CONCATENATEX(
        Employee,
        Employee[BK_Employee#ID] & ";" & Employee[FirstName] & " " & Employee[LastName],
        "|",
        Employee[BK_Employee#ID], ASC
    )
```

⚠️ **The exact string shape this needs to produce — delimiters, and which value comes first in a key/value pair — is dictated by the consuming visual property, not a modeling decision.** Check the consuming visual's own skill for that property's exact contract before writing a measure like this — `accotool-ai-customvisual-accomasterdata` §10 for accoMASTERDATA (its confirmed shape is `"key;label|key;label"`, stored value first), `accotool-ai-customvisual-accoplanning` for accoPLANNING. accoCOMMENT has no skill yet; treat its property contracts as undocumented rather than assuming they match either of the other two. Getting the order backwards produces a measure that looks entirely correct in a DAX query but silently drives the visual wrong (confirmed: a `"Label;Key"` order wrote the wrong value on selection instead of erroring).

---

## 9. Naming Constraints That Affect Measures

🟢 **A measure cannot share a name with a column in the same table.** If a measure needs a name that collides with a column elsewhere in the model (e.g. a transaction-key measure named after a foreign business key), it must live on a *different* table than that column.

🟢 **Measure naming can be load-bearing for writeback, not just cosmetic.** A visual may require its bound measure to carry a specific name that the writeback mechanism matches against downstream. If a column's name conflicts with the measure name writeback needs, rename the column's display name (leaving `sourceColumn` unchanged) rather than compromising the measure's required name.

---

## 10. Model View Layout

🟢 The organization's convention, confirmed against a real reference build: fact table(s) at the **bottom-left** of the canvas, dimension tables arranged in a **row above** them, and config/metadata tables (`Config_Connection`, `Config_Writeback`) kept in their **own separate column**, off to the side, not mixed into the star-schema arrangement.

**This is not exposed as a structured parameter anywhere in `table_operations`, `model_operations`, or `relationship_operations`** — verified directly against their schemas; none has a position/coordinate field. Layout lives in a separate file, `diagramLayout.json`, alongside the semantic model's TMDL definition. Edit it directly the same way this project already edits PBIR files directly (edit → reload — never rely on Desktop's own save to preserve a hand-edited layout).

Confirmed shape, captured from a real file:

```json
{
  "version": "1.1.0",
  "diagrams": [
    {
      "ordinal": 0,
      "scrollPosition": { "x": 0, "y": 0 },
      "nodes": [
        {
          "location": { "x": 0, "y": 0 },
          "nodeIndex": "{TableName}",
          "nodeLineageTag": "{the table's own lineageTag GUID}",
          "size": { "height": 300, "width": 234 },
          "zIndex": 0
        }
      ],
      "name": "All tables",
      "zoomValue": 100,
      "pinKeyFieldsToTop": false,
      "showExtraHeaderInfo": false,
      "hideKeyFieldsWhenCollapsed": false,
      "tablesLocked": false
    }
  ],
  "selectedDiagram": "All tables",
  "defaultDiagram": "All tables"
}
```

⚠️ **`nodeLineageTag` must match the real table's own `lineageTag`** from the model — fetch it via `table_operations` `Get`/`List` or `ExportTMDL` before writing this file; never invent one. `nodeIndex` is the table name as it appears in the model.

**Coordinate convention: x increases rightward, y increases downward** — a *smaller* y places a table higher on the canvas, not lower. To reproduce the standard layout: give fact table(s) the largest y and smallest x (bottom-left), give dimension tables a smaller y (higher up) spread across increasing x values (a row above the fact), and give config/metadata tables their own x column separate from both.

