# accoMASTERDATA — accoTool Custom Visual Configuration

**Status:** in progress — see §12 for what isn't covered yet.

**Source of truth for what's configurable at all:** [`accomasterdata-schema.json`](accomasterdata-schema.json) in this same folder is the visual's own property catalog — every `FormattingPaneSettings` object group (`Connection`, `TransactionKeys`, `Datagrid`, `Measures`, `Validation`, `Miscellaneous`, `CustomColumns`, `LockCells`, `DataReductionCustomization`), each entry mapping its Format-pane display name to the internal property name used in `objects.<group>[].properties.<name>` in `visual.json`, plus a `JsonSchemas` section giving the inner shape of every stringified-JSON property (`themeJSON`, `initialState`, `conditionalFormatting`, etc.). It also has a separate `CustomVisualSettings` section — settings persisted outside `visual.json`/the Format pane entirely (browser-local-storage-style, keyed per report), not something this doc's `objects.*` patterns apply to. This `.md` file only documents the subset of that catalog that's actually been built and verified in this project (🟢/🟡), or explicitly ruled out (⚠️) — §12 lists the rest of the catalog that's still unbuilt. When a user's scenario needs a property, check this schema first for the exact name and group, then check whether §§1–10 below already cover it before hand-authoring it blind.

**Confidence markers:**
🟢 Confirmed — verified directly.
🟡 Working baseline — not yet independently verified.
⚠️ Open — a known gap or unresolved question.

**On the DAX shown below:** a few properties in this file (§5, §10) can only be described in terms of *which* measure a property must bind to and *what shape it must return* — a property of this visual's own binding mechanism, not a modeling decision. DAX snippets here illustrate that requirement's shape only; authoring, naming, and organizing any actual measure is `accotool-ai-semantic-model`'s content.

---

## 1. Placing an accoMASTERDATA visual

**Visual type identifier:** `accoMASTERDATA_4DAA52ABFBF441E2A7898A79384CAFB9`

Two things are required to place the visual, both hand-authored directly as files (see §11 for why):

**(a) Register the visual type on the report**, in `<Report>/definition/report.json`:
```json
"publicCustomVisuals": [
    "accoMASTERDATA_4DAA52ABFBF441E2A7898A79384CAFB9"
]
```
This array lives alongside `themeCollection`/`objects`/`resourcePackages` at the top level of `report.json`. No corresponding entry is needed in `resourcePackages` — the visual type string alone is sufficient.

**(b) Create the visual container**, a new file at `<Report>/definition/pages/<pageId>/visuals/<visualId>/visual.json`. A freshly-placed, unconfigured instance needs nothing beyond its type and a position — no `query` block and no `objects` block exist yet at this stage:
```json
{
  "$schema": "https://developer.microsoft.com/json-schemas/fabric/item/report/definition/visualContainer/2.11.0/schema.json",
  "name": "<20-character-hex-id>",
  "position": {
    "x": 40, "y": 40, "z": 0,
    "height": 640, "width": 1200,
    "tabOrder": 0
  },
  "visual": {
    "visualType": "accoMASTERDATA_4DAA52ABFBF441E2A7898A79384CAFB9",
    "drillFilterOtherVisuals": true
  }
}
```
⚠️ The `$schema` version should be copied from an existing `visualContainer` file in the same report rather than assumed to be `2.11.0` universally — matching whatever `report.json`'s `reportVersionAtImport.visual` says.

🟢 A `reload` (not a Desktop UI save) is what picks up this kind of file edit — Desktop overwrites file edits with its own stale in-memory copy on a save, so a save is only useful when a change was made *through* Desktop's own UI and needs reading back into the files. When more than one Desktop window is open on the same file, each needs its own reload, and which window is actually in use isn't safe to assume without checking directly.

---

## 2. Binding data roles (rowIds + measures)

Added under `visual.visual.query.queryState` (a freshly-placed visual has no `query` block at all until the first field is bound — see §1):

```json
"query": {
  "queryState": {
    "rowIds": {
      "projections": [
        {
          "field": { "Column": { "Expression": { "SourceRef": { "Entity": "<TableName>" } }, "Property": "<KeyColumn>" } },
          "queryRef": "<TableName>.<KeyColumn>",
          "nativeQueryRef": "<KeyColumn>"
        }
      ]
    },
    "measures": {
      "projections": [
        {
          "field": { "Column": { "Expression": { "SourceRef": { "Entity": "<TableName>" } }, "Property": "<ColumnName>" } },
          "queryRef": "<TableName>.<ColumnName>",
          "nativeQueryRef": "<ColumnName>"
        }
        /* one entry per displayed column */
      ],
      "showAll": true
    }
  }
}
```

- `rowIds` takes exactly the table's key column — one projection, `Column` (not `Measure`) type.
- `measures` takes one projection per displayed column — audit/system columns (`UpdatedBy`, `CreateDateTime`, `UpdateDateTime`) are conventionally left out of this well, since they're metadata rather than something a user reads or edits in the grid.
- `showAll: true` on the `measures` projections block matches what Desktop itself generates when a field is bound through the UI.
- 🟢 **Every column placed in the `measures` well is editable by default — no `objects.measures` entry is needed to enable it.** §3 covers the property that restricts a field instead.

---

## 3. Field editability defaults to ON — `editable: false` restricts a specific field

🟢 Fields in the `measures` well are editable and write back correctly with no per-field config at all. `objects.measures[].properties.editable` exists to **override the default down** — typically to lock a system-managed or approval-gated column, not to opt a field into editability:

```json
"measures": [
  {
    "properties": {
      "editable": { "expr": { "Literal": { "Value": "false" } } }
    },
    "selector": { "metadata": "<TableName>.<ColumnName>" }
  }
]
```
`selector.metadata` is the field's `queryRef`.

🟢 Desktop's own column-header settings menu in the grid has a live toggle for the same property — a change made there only becomes visible in the file after a Desktop save.

**Boolean fields — display style, via the same `objects.measures[]` entry:**
```json
"booleanFormatting": { "expr": { "Literal": { "Value": "true" } } }
```
🟢 This is not an on/off switch for whether the field is boolean-formatted at all — both values render the field as a boolean widget, in the same `measures[]` entry alongside `editable`. `true` renders a toggle switch; `false` renders a checkbox.

Row creation (`CREATE ROW`) against an `IDENTITY` primary key works with no special configuration — no audit-log properties are required for core writeback (`UPDATE`/`CREATE ROW`) to succeed (see §6).

---

## 4. Renaming a field's display label without breaking writeback

A column can carry a friendlier grid label than its physical SQL column name while still writing to the correct column, using two independent mechanisms:

**(a) Rename the display label** — standard Power BI field renaming, nothing accoTool-specific. It changes the query projection, not `objects`:
```json
{
  "field": { "Column": { "Expression": { "SourceRef": { "Entity": "<TableName>" } }, "Property": "<ColumnName>" } },
  "queryRef": "<TableName>.<ColumnName>",
  "nativeQueryRef": "<Friendly Label>",
  "displayName": "<Friendly Label>"
}
```
`queryRef`/`Property` — the actual field binding — stays untouched. Only `nativeQueryRef`/`displayName` change.

**(b) Point writeback at the real column** — an entry in `objects.connection[]` (an array: one entry holds the credential/audit properties from §5, additional entries each target one renamed field):
```json
{
  "properties": {
    "writebackColumnName": { "expr": { "Literal": { "Value": "'<ColumnName>'" } } }
  },
  "selector": { "metadata": "<TableName>.<ColumnName>" }
}
```
`selector.metadata` is the field's `queryRef` — the same per-field selector pattern as `editable` in §3, in the `connection` object group instead of `measures`.

⚠️ Hand-authoring this has occasionally failed unpredictably (a field with a correct, unchanged `writebackColumnName` entry started rejecting writes after other entries were added elsewhere in the same array), with no identified trigger or reliable workaround. A live row save is the only reliable confirmation after any hand-authored change to `writebackColumnName` — matching a previously-working pattern is not a guarantee, given this failure mode.

🟡 In the generated `INSERT`, fields with a `writebackColumnName` override appear out of their natural column order — grouped together near the end. Writeback still succeeds; this appears to be cosmetic.

---

## 5. Connection & credential binding

Object group: `connection` (added to `visual.objects`, alongside `query`).

**Credential/connection properties bind to measures, not literals:**
```json
"connection": [
  {
    "properties": {
      "serverName": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection Server" } } },
      "databaseName": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection Database" } } },
      "databaseUsername": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection User" } } },
      "databasePassword": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection Password" } } },
      "schemaName": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection Schema AM" } } },
      "tableName": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection Table AM" } } },
      "auditLogCurrentUser": { "expr": { "Measure": { "Expression": { "SourceRef": { "Entity": "_Measures" } }, "Property": "Connection CurrentUser" } } }
    }
  }
]
```
The measure names here match the standard connection-measure set that `accotool-ai-semantic-model` owns — this file only states which measure each property binds to, not how those measures are authored.

**Properties that must stay absent, not just unset-by-default:**
- `authenticationMethod` — setting it, even to a plausible-looking value, silently reverts the whole visual to its onboarding/setup screen with no error.
- `encryptedUser`/`encryptedPassword` — visual-generated output blobs from the manual UI-entry flow, not input properties. Leaving old ones in place alongside measure bindings causes `"Encrypted message length is invalid"` (a mixed-mode state).

🟢 **Any Desktop save reverts the automated-credential state.** A report-level save, or just the visual's own in-grid row save (including on a failed attempt), rewrites `databasePassword` back to the literal `'********'` and regenerates fresh `encryptedUser`/`encryptedPassword` blobs, every time, with no known exception — no way has been found to make the automated-credential state survive a Desktop save. Recovery after such a save follows the same pattern each time: delete `encryptedUser`/`encryptedPassword` entirely, rebind `databasePassword` back to the `Connection Password` measure, then reload (not save).

---

## 6. Audit-log block

**Audit-block column-name properties are literal strings, not measures**, in the same `connection` object group as the credential properties above (not a separate "Audit" group — easy to miss going by property-group names alone):
```json
"auditLogUserDetails": { "expr": { "Literal": { "Value": "'UpdatedBy'" } } },
"auditLogTimestamp":   { "expr": { "Literal": { "Value": "'UpdateDateTime'" } } },
"auditLogEnabled":      { "expr": { "Literal": { "Value": "true" } } },
"auditLogSchema":       { "expr": { "Literal": { "Value": "'accoTOOL$Base'" } } },
"auditLogTable":        { "expr": { "Literal": { "Value": "'Log_Audit'" } } },
"auditLogRowKeyColumn": { "expr": { "Literal": { "Value": "'RowKey'" } } },
"auditLogType":         { "expr": { "Literal": { "Value": "'TransactionType'" } } },
"auditLogSQLCommand":   { "expr": { "Literal": { "Value": "'SQLCommand'" } } }
```

- `auditLogUserDetails`/`auditLogTimestamp` name the who/when columns on the **separate audit table** — the friendly Format-pane labels are "Username Stamp Column Name" / "Timestamp Column Name".
- `auditLogSchema`/`auditLogTable` name the **physical** location of that audit table — the same convention as the main writeback table's `schemaName`/`tableName`, resolved independently of whatever the model loaded through.
- `auditLogRowKeyColumn`/`auditLogType`/`auditLogSQLCommand` are literal **column names on that audit table** (not values) — they tell the visual which column to write the row key, transaction type, and generated command text into.
- `TransactionType` is populated with the literal `'create'` for row creation and `'update'` for an edit to an existing row.
- `SQLCommand` receives the full generated `INSERT`/`UPDATE` statement with literal values inlined (not parameterized) — a useful record of exactly what was written.

⚠️ This is separate from the main writeback table's own stamping: `Dim_{Name}#AM`'s own `UpdatedBy`/`UpdateDateTime` columns get set automatically by the visual's generated statement, with no separate configurable property — it simply assumes those exact column names exist on the writeback table (they always do, per `accotool-ai-sql-schema`'s mandatory Dimension columns). `auditLogUserDetails`/`auditLogTimestamp` concern only the separate audit table.

🟢 This audit block is a genuinely optional layer, separable from core writeback — `UPDATE`/`CREATE ROW` (including `IDENTITY`-key generation and the main table's own stamping) work independently of whether it's configured at all.

---

## 7. Grid styling

Object group: `datagrid` (added to `visual.objects`, alongside `connection`/`measures`). All properties are literals.

```json
"datagrid": [
  {
    "properties": {
      "themeJSON": { "expr": { "Literal": { "Value": "'{\"palette\":{\"primary\":{\"main\":\"<hex>\"},\"secondary\":{\"main\":\"<hex>\"}},\"shape\":{\"borderRadius\":<number>}}'" } } },
      "rowHeight": { "expr": { "Literal": { "Value": "<number>D" } } },
      "headerHeight": { "expr": { "Literal": { "Value": "<number>D" } } },
      "cellFontSize": { "expr": { "Literal": { "Value": "<number>D" } } },
      "headerFontSize": { "expr": { "Literal": { "Value": "<number>D" } } },
      "headerFontColor": { "expr": { "Literal": { "Value": "'<hex>'" } } },
      "headerBackgroundColor": { "expr": { "Literal": { "Value": "'<hex>'" } } },
      "lockedCellsBackgroundColor": { "expr": { "Literal": { "Value": "'<hex>'" } } },
      "showAggregationLabels": { "expr": { "Literal": { "Value": "true" } } }
    }
  }
]
```

- `themeJSON` is a JSON-string-within-a-string (note the escaped inner quotes) carrying a palette (`primary`/`secondary` `main` colors) and `shape.borderRadius`. It sets the overall theme; `headerFontColor`/`headerBackgroundColor` are separate literal overrides on top of it, not derived from it — the palette alone does not determine header colors.
- Numeric properties (`rowHeight`, `headerHeight`, `cellFontSize`, `headerFontSize`) take a bare number with a trailing `D` (e.g. `50D`), matching the numeric-literal convention used elsewhere in this visual (`editable`'s boolean literals, by contrast, use `true`/`false` with no suffix).
- The visual also ships named style presets (e.g. a "casual" preset) selectable only from its own Format pane — picking one writes a full batch of `datagrid`/toolbar properties (including a `themeJSON` blob) in one go. Their exact values aren't documented anywhere outside the visual itself; reading them back from a real file after selecting one in the UI, or hand-authoring explicit values directly as above, are the two working approaches — guessing at a preset's colors is not.
- A related toolbar-styling set (`toolbarLabels`, `saveCount`, `toolbarBackgroundColor`, `toolbarFontColor`, `toolbarFontSize`) lives in the `miscellaneous` object group, not `datagrid`.

**Column order and width — `datagrid[].properties.initialState`.** A JSON-string-within-a-string (same escaping convention as `themeJSON`) holding the grid's UI state, written by the visual's own "Save state" action — not derived from the field order in `query.queryState`. The relevant parts:
```
"columns": {
  "orderedFields": ["<display name>", "..."],
  "dimensions": { "<display name>": { "width": <number>, "minWidth": <number>, "maxWidth": <number> } }
}
```
`orderedFields` lists columns by their **display name** (the renamed label if one is set, per §4 — not the physical column or `queryRef`), in display order. Column reordering is persisted by reordering columns in the grid and using "Save state" — there's no separate `objects.connection`/`objects.measures` property for column order.

⚠️ The same blob also carries filter/sort/pagination state (`filterModel`, `sortModel`, `pagination.rowCount`, etc.) alongside `columns`. It's not confirmed which parts are load-bearing configuration versus an incidental snapshot of whatever the grid happened to be showing at save time — treating the whole thing as opaque UI state captured by "Save state", rather than something to hand-author selectively, is the safer approach.

---

## 8. Shadow calculations — computing a field's value from other fields on the row

Object group: `validation`, one property, the same JSON-string-in-a-literal pattern as `themeJSON`/`initialState`:
```json
"validation": [
  {
    "properties": {
      "calculationSettings": {
        "expr": {
          "Literal": {
            "Value": "'[{\"title\":\"<RuleName>\",\"column\":\"<target display name>\",\"formula\":\"<expression>\"}]'"
          }
        }
      }
    }
  }
]
```
The inner value is a JSON array of rules. `column` is the **target field's display name** (per §4's renaming, not the physical column) — the calculated value is written there, never included as an assignment inside `formula` itself. `formula` supports ternary conditionals (`condition ? a : b`), arithmetic (`+ - * /`), string equality (`==`/`!=`), and `[ColumnName]` references to other fields on the same row.

🟢 **This recalculates only when triggered by an edit to some other field on the row — it is not a continuously-applied display formula.** A column governed by a shadow calculation does not update merely from being rendered or from the report loading; editing an unrelated field on the same row is what triggers the recalculation and write-back.

🟢 **Referencing the row-key field (the `rowIds` column, e.g. `BK_Employee#ID`) inside a plain arithmetic formula works and resolves to its real value** — confirmed directly in SQL: a formula of `1000 + [BK_Employee#ID]` produced exactly that sum for the edited row.

⚠️ **An earlier attempt using a ternary that compared the row-key field (`[BK_Employee#ID] >= 0 ? ... : 0`) produced the `else`-branch value for every row instead of the real calculation — but the arithmetic-only formula above resolved the same field correctly, so "row-key fields don't resolve" is not the explanation.** The actual cause of that earlier result is still unknown — candidates include the comparison operator specifically, or something else about that formula's shape, not the row-key reference itself. Neither "resolves fine" nor "resolves blank" can be assumed as a blanket rule for a new formula; a ternary with a comparison on a row-key field specifically remains unverified.

⚠️ **Real risk: a column with a uniqueness constraint is unsafe to target until the formula is verified correct.** If a formula's result ends up the same for every row (as happened with the earlier ternary, where every row fell through to the same `else`-branch value), every subsequent edit to *any* row recomputes and tries to write that same duplicate value — permanently blocking writeback with a unique-constraint violation until the `calculationSettings` entry is removed or fixed. Testing a new formula shape against a non-unique column first is the safer approach whenever there's doubt.

---

## 9. Reload gotcha: a timeout/error from the bridge doesn't always mean the reload failed

🟢 After editing `visual.json` and calling `powerbi-desktop reload`, the bridge can report a timeout or `"Host is not ready to accept operations"` — and the reload can still have actually succeeded underneath. A reload error is not ground truth on its own for whether the reload failed — checking the actual state (what's showing in Desktop, or `powerbi-desktop status` for a healthy `connected` bridge on the same process) is the reliable check, before assuming the edit didn't take effect or reaching for a more drastic fix (force-closing Desktop, re-issuing the reload).

🟢 One confirmed, nameable cause of `"Host is not ready"`: a "potential security risk" dialog (the kind that appears around native/dynamic database queries) blocking the bridge until dismissed. This is handled the same as any other blocking modal — dismissing it, then re-checking `status`, rather than force-closing Desktop.

🟢 **A stray or mismatched brace from a hand-edit doesn't fail loudly right away.** It can sit silently in `visual.json` — `reload` itself may even report success — until Desktop's "Apply external changes" banner tries to fully re-parse the whole PBIP project, at which point it surfaces as a dramatic crash-style error dialog with a full stack trace ("JsonToken EndObject is not valid for closing JsonType Array..."), even though the underlying problem is an ordinary JSON syntax error. Validating that the file still parses as JSON after every hand-edit, before reloading — e.g. `Get-Content <file> -Raw | ConvertFrom-Json` — catches this class of mistake immediately instead of via a scary dialog later.

---

## 10. Dropdowns

Same `objects.measures[]` entry as `editable`/`booleanFormatting`, keyed by `selector.metadata`:
```json
"dropdownEnabled": { "expr": { "Literal": { "Value": "true" } } },
"dropdownFormula": { "expr": { "Literal": { "Value": "'<item>|<item>|...'" } } },
"dropdownItemDelimiter": { "expr": { "Literal": { "Value": "'|'" } } }
```
🟢 **Confirmed working** for a plain list of literal values — each item is both the displayed label and the stored/written value. Useful as-is for a foreign-key-style field where the valid values are literal keys (e.g. a self-referencing `FBK_{Name}#ID` "Manager" field): listing the currently-valid key values directly writes back exactly the value picked.

🟢 **`dropdownKeyValueEnabled: true` shows a friendly label while storing a different value — confirmed working, with a specific pair order.** `dropdownFormula` must be `"Key;Label|Key;Label|..."` — **the stored value first, the displayed label second** (the reverse of the intuitive "Label;Key" guess — that ordering was tried first and silently wrote the wrong value, including once causing a foreign-key violation against a value that was never actually chosen). With the correct order: the dropdown shows the label, and saving writes the key.

🟢 **`dropdownFormula` can be measure-bound for a genuinely dynamic list, both plain and key/value.** Confirmed for both:
```json
"dropdownFormula": {
  "expr": {
    "Measure": {
      "Expression": { "SourceRef": { "Entity": "_Measures" } },
      "Property": "<MeasureName>"
    }
  }
}
```
**Requirements this property imposes on the measure (an accoMASTERDATA-visual requirement, not a semantic-modeling decision — owned here, not by `accotool-ai-semantic-model`):**
- The measure must be hosted on a table **other than** the one this visual's own `rowIds`/`measures` data roles are bound to (here, `Employee`). A measure created directly on that same bound table made the **entire `objects.measures[]` entry for the field disappear from the Format pane** when referenced — not wrong output, the whole entry vanished. Moving the identical measure to a table with no row context of its own fixed it immediately. This project already has such a table, `_Measures` — `accotool-ai-semantic-model` documents how it's built and why every standalone measure belongs there.
- The measure's *returned string* must exactly match what the property expects: for a plain dropdown, a single delimiter-separated list (`"value|value|..."`); for a key/value dropdown, delimiter-separated `"key;label|key;label|..."` pairs, key first. This shape is a property of this visual's parser, not a semantic-modeling decision — a new measure feeding a dropdown is authored under `accotool-ai-semantic-model`'s conventions (table hosting, naming), but needs to produce exactly this string shape.
- A `Column`-type binding (as opposed to `Measure`) to an unrelated table was also tried and failed differently — an explicit `UnsupportedProjectionIndexInSemanticQuery` error rather than a silent drop. `Measure` is the only confirmed-working expr type for a dynamic dropdown list.

⚠️ Whether the same-table failure is specifically because the bound table already carries row/column context in the visual's own query, versus some other difference between the failing and working attempts, was never isolated by testing a measure on a third, unrelated-but-not-`_Measures` table. The practical rule (host it off the bound table, in `_Measures`) holds regardless of the deeper mechanism.

🟡 A dedicated settings dialog for this visual (opened from within Desktop, separate from the standard Format pane) exposes more dropdown properties than documented above: `dropdownCascadingDependency` (chains one dropdown's options to another field's current value — literal, a field display name or empty) and `dropdownAllowFreeSolo` (whether a typed value outside the list is accepted). Neither has been deliberately tested yet — values seen so far look like the visual's own auto-populated defaults from opening that dialog, not anything intentionally configured.

---

## 11. Why this is hand-authored rather than CLI-driven

🟡 The Microsoft `powerbi-report-author` CLI's live discovery commands (`formatting describe-object`, `formatting search`) have no introspection into accoMASTERDATA at all — `catalog describe accoMASTERDATA` returns `VISUAL_TYPE_UNKNOWN`, and `formatting describe-object` returns `FORMATTING_OBJECT_UNKNOWN` with no available objects. accoMASTERDATA is a proprietary `.pbiviz` outside Microsoft's catalog, so there is no CLI fallback for it — every property here comes from direct knowledge of the visual's own schema or from reading a real working file, not from asking the CLI.

---

## 12. Not yet covered — do not assume or guess ahead of building it

Cross-referenced against every object group in `accomasterdata-schema.json`. Nothing below has been built or verified in this project — treat each as reachable-but-unknown, not as unsupported. Before hand-authoring any of these, re-check the schema for the exact property name/group, since it's the only source for them right now.

**Previously flagged, still open:**
- `dropdownCascadingDependency` and `dropdownAllowFreeSolo` (`measures`, §10) — seen but never deliberately tested
- Named style presets' underlying values (`datagrid`, §7) — hand-authored explicit properties are covered, presets themselves are not
- What specifically made an earlier ternary/comparison formula fail against a row-key field when plain arithmetic on the same field succeeded (§8) — unconfirmed
- `conditionalFormatting` (`validation`) — cell-lock/styling rules, untested in this project

**Entire `measures` field-type families untouched** (§3/§10 only cover editable/boolean/dropdown): URL display (`urlEnabled`, `displayURLText`, `urlDisplayType`), text area (`textAreaEnabled`, `bindingTextAreaMultilines`), tags (`tagsEnabled`, `tagDelimiter`, `tagFilled`, `tagColor`, `tagHeight`, `tagBorderRadius`), rich text (`richTextEnabled`, `allowRichTextPlainCopy`, `plainTextAsWriteback`), date/time pickers (`dateEnableTimeEdit`, `dateFormat`, `timeFormat`, `allowTime`, `legacyDate`, `datetimeEnabled`, `toggleTimeInDateFormat`, `dateTimeFlipped`), value-bar/graph formatting (`gradientColors`, `graphMinValue`, `graphMaxValue`, `graphAutoCalculateMinValue`, `graphAutoCalculateMaxValue`, `graphAllowFreeSolo`, `percentagesEnabled`, `togglePercentagesNumber`), number formatting (`separators`, `decimalPlaces`, `customFormat`), single-select (`singleSelectOption`), required-field enforcement (`required`), per-field grid appearance (`rowGridAlignmentPerColumn`, `columnHeaderAlignmentPerColumn`, `headerBackgroundColor`, `headerFontColor`, `headerFontStyle`, `cellBackgroundColor`, `cellFontColor`, `showCellLockInGrid` — note these are `measures`-level per-field overrides, distinct from the `datagrid`-level grid-wide properties of the same name in §7), row-creation defaults (`excludeFromCreation`, `defaultValueOnCreateEnabled`, `textDefaultValueOnCreate`, `booleanDefaultValueOnCreate`, `numberDefaultValueOnCreate`).

**Whole object groups untouched:**
- `TransactionKeys` (`BooleanTransactionKeyOnRowCreation`, `TextTransactionKeyOnRowCreation`, `NumericTransactionKeyOnRowCreation`) — nothing known about what these do or when they apply, despite row creation itself (§3) working without them
- `CustomColumns` (`customColumnDefinitions`) — a JSON array of "calculated/custom column definitions" per the schema; relationship to the `validation.calculationSettings` shadow-calculation mechanism in §8 (which also computes a column's value) is unconfirmed — may overlap, may be a different feature entirely
- `LockCells` (`allowRowCreation`) — name looks adjacent to `miscellaneous.allowCreateRow` below; whether these are two independent switches or duplicates is unconfirmed
- `DataReductionCustomization` (`rowCount`) — likely a row-limit/data-reduction setting, unverified

**`connection` group, beyond §5/§6:** `licenseKey`, `useSelfhostedAPI`, `SelfhostedAPIURL`, `isFabric`, `tenantId`, `encryptedTenantId`, `requestTimeout`, `performMergeInsteadOfUpdate` (this last one in particular looks directly relevant to writeback semantics — whether `UPDATE` merges or replaces — and is worth prioritizing if a scenario needs partial-row updates)

**`datagrid` group, beyond §7:** `infiniteScroll`, `scrollToCell`, `themeJSONLastSave` (looks like a visual-managed snapshot, not something to hand-author), `fontFamily`, `columnHeaderAlignment`, `rowDataAlignment`, `rowHeightIndividual`, `enableCreateRowModal`, `lockedCellsFontColor`, `cellFontColor`, `applyLightenTheme`

**`validation` group, beyond §8:** `min`, `max`, `regexString`, `minDateTime`, `maxDateTime`, `groupingSettings`, `groupingExpandAll`, `rowGroupingExpandAll` — row grouping in particular is a distinct grid feature from anything covered so far

**`miscellaneous` group, beyond the toolbar-styling set named in §7:** `copyWithFormatting`, `allowCreateRow`, `ignoreBlankRowsOnSave`, `allowDeleteRow`, `createNewRowWithTab`, `highlightWholeRowOnFocusCell`, `resetApplication`, `localStoragageReportId`

**`CustomVisualSettings`** (a separate top-level key in the schema, sibling to `FormattingPaneSettings` — persisted outside `visual.json`/the Format pane, not an `objects.*` pattern; see the note at the top of this file): `ColumnGroupsState`, `ColumnWidths`, `RowHeightIndividualStorage`, `RecentColors`, `ReadNotifications`. ⚠️ `ReadNotifications`'s `InternalPropertyName` in the schema is literally `accoPLANNING_ReadNotifications`, not an accoMASTERDATA-prefixed key — either a copy-paste artifact from accoPLANNING's own schema file, or this setting is genuinely shared/cross-visual. Don't assume either explanation; verify against a real report before relying on it.

Each of these gets added to §§1–11 (with its own confidence marker) once it's actually built and verified — don't move an entry out of this section on schema presence alone.
