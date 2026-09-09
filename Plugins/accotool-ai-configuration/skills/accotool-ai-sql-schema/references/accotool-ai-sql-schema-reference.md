# accoTOOL SQL & Schema — Build Reference

The DDL templates, naming conventions, and per-pattern build detail for `accotool-ai-sql-schema`.
SKILL.md holds the scope, build order, pre-flight discovery, and the standing rules — read it first;
this file is what it points into once a build is actually underway.

**Confidence markers** (same convention as SKILL.md):
🟢 Confirmed — verified against a real, currently-deployed database.
🟡 Working baseline — adopted as the standard going forward per an explicit decision, pending independent confirmation.
⚠️ Open — a known gap or unresolved question, flagged rather than guessed at.

---

## 3. Naming Convention Reference

```
SCHEMAS
  Module:    accoTOOL${ModuleName}          e.g. accoTOOL$SalaryPlanning
  Base:      accoTOOL$Base
  Datamart:  dmAccoTOOL_{Name}              e.g. dmAccoTOOL_SalaryPlanning

TABLES (module schema)
  Dim:            Dim_{Name}#{Visual}                Dim_Employee#AM
  Fact (normal):  Fact_{Name}#{Visual}               Fact_SalaryPlan#AP
  Fact (RAW):     Fact_{Name}_RAW#{Visual}           Fact_SalaryPlan_RAW#AP
  Fact (current): Fact_{Name}_Current                Fact_SalaryPlan_Current
  Comment (AC):   Fact_{Name}_Comment#AC             Fact_SalaryPlan_Comment#AC
  Config:         Config_{Name}                      Config_VersionCopy
  Bridge:         Bridge_{PrimaryDim}{SecondaryDim}  Bridge_ProjectEmployee  (⚠️ no worked example yet)

TABLES (base schema — shared, see §4)
  Config_Connection, Config_Writeback, Log_Audit — one of each, ever, for the whole database.

VIEWS
  Module:          vw_{TableType}_{Name}             vw_Dim_Employee
  Datamart Fact:   _{Name}                           _SalaryPlan
  Datamart Dim:    {Name}                            Employee

COLUMNS
  Identity PK:      BK_{Name}#ID                     BK_Employee#ID
  Foreign BK:       FBK_{DimName}#{Col}              FBK_Employee#ID  (self-reference is valid — see §5.1)
  Integer date key: {ColumnName}_Int                 StartDate_Int

STORED PROCEDURES
  Auto-run (scanned and executed by the warehouse orchestration after Gold-layer processing): sp_work_{Name}
  Other:                                                                                        sp_{Name}

FUNCTIONS
  Table-valued:  tvf_{Name}       Scalar:  svf_{Name}

TRIGGERS
  TR_{TableName}_{Timing}_{Event}_{Purpose}
  e.g. TR_Fact_SalaryPlan_RAW#AP_After_Insert_MergeToCurrent

INDEXES
  IX_{TableName}_{IndexName}

VISUAL CODES:  accoPLANNING = AP  ·  accoMASTERDATA = AM  ·  accoCOMMENT = AC
```

🟢 **Mandatory columns**

| Table type | Columns |
|---|---|
| Fact | `UpdatedBy NVARCHAR(200) NOT NULL`, `UpdateDateTime DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()` |
| Dimension | above, plus `CreateDateTime DATETIME2(3) NOT NULL DEFAULT SYSUTCDATETIME()`, plus `IsActive BIT NOT NULL DEFAULT 1` (soft-delete flag — used everywhere in practice even though not called out in the original framework spec) |
| Shared audit log (`accoTOOL$Base.Log_Audit` only — see §4.3) | `UpdatedBy`, `UpdateDateTime`, `RowKey NVARCHAR(100) NOT NULL`, `TransactionType NVARCHAR(100) NOT NULL`, `SQLCommand NVARCHAR(4000) NOT NULL` — exactly the accoTOOL Solution Framework Documentation (external, not part of this repo) §4.3 list, no more |

### 3.1 Special values and derived columns

**Far-future sentinel date (`2152-12-31`)** — used wherever an open-ended date range needs a non-NULL upper bound. Applied in the **module view layer**, not the base table — the base table column stays nullable:

```sql
ISNULL([TerminationDate], CONVERT(date, '2152-12-31')) AS [TerminationDate]
```

**Integer date keys** — dates are commonly also exposed as a `yyyyMMdd`-format integer alongside the date column itself, for downstream integer-keyed joins:

```sql
CAST(FORMAT(ISNULL([TerminationDate], CONVERT(date, '2152-12-31')), 'yyyyMMdd') AS INT) AS [TerminationDate_Int]
```

**UTC storage / midnight-timestamp gotcha** ⚠️ real, documented issue — dates are stored in UTC; a downstream consumer that applies a positive UTC-offset timezone conversion can visually shift a midnight-UTC date to the previous day. Mitigate at the view layer by appending noon instead of midnight where this matters:

```sql
CAST(CAST([DateColumn] AS DATE) AS DATETIME) + '12:00:00' AS [DateColumn_Adjusted]
```

---

## 4. Base Schema (`accoTOOL$Base`)

There is **exactly one** `accoTOOL$Base` per database, shared by every module. Check what already exists (§2.2) before creating any of the following — most databases past their first module will already have some or all of it.

```sql
CREATE SCHEMA [accoTOOL$Base];
```

### 4.1 Config_Connection 🟢 single shared row — corrected from v1.0

**This table holds exactly one row for the whole database**, describing the single shared writeback identity (§8) — not one row per module. This was the v1.0 skill's stated design (a "resolved decision," in that document's words); it has since been confirmed to be wrong. A single shared identity is the real, current standard.

```sql
CREATE TABLE [accoTOOL$Base].[Config_Connection] (
    [ConnectionKey]  INT IDENTITY(1,1) NOT NULL,
    [ServerName]     NVARCHAR(200)     NOT NULL,
    [DatabaseName]   NVARCHAR(200)     NOT NULL,
    [AuthMethod]     NVARCHAR(50)      NOT NULL DEFAULT 'SQLUser',
    [DBUser]         NVARCHAR(200)     NULL,
    [DBPassword]     NVARCHAR(500)     NULL,
    [UpdatedBy]      NVARCHAR(200)     NOT NULL,
    [UpdateDateTime] DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Config_Connection PRIMARY KEY ([ConnectionKey])
);
```

⚠️ `AuthMethod` here is a metadata label describing the stored credential, unrelated to any visual-side authentication property of the same name — do not conflate the two when this table is consumed downstream.

`DBPassword` is stored in plaintext by design — this is a deliberate, accepted trade for PoC/demo builds with a least-privilege writeback identity. Do not encrypt it or omit it; both break downstream consumption. This is out of scope to justify further here — see the credential-automation documentation this project already carries if the reasoning is needed.

### 4.2 Config_Writeback 🟢 confirmed, real, deployed

```sql
CREATE TABLE [accoTOOL$Base].[Config_Writeback] (
    [WritebackKey]   INT IDENTITY(1,1) NOT NULL,
    [ModuleName]     NVARCHAR(100)     NOT NULL,
    [SchemaName]     NVARCHAR(100)     NOT NULL,
    [TableName]      NVARCHAR(200)     NOT NULL,
    [VisualCode]     NVARCHAR(10)      NOT NULL,  -- AP | AM | AC
    [IsActive]       BIT               NOT NULL DEFAULT 1,
    [UpdatedBy]      NVARCHAR(200)     NOT NULL,
    [UpdateDateTime] DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Config_Writeback PRIMARY KEY ([WritebackKey])
);
```

Populate with one row per writeback table, by hand, at the point that table is created:

```sql
INSERT INTO [accoTOOL$Base].[Config_Writeback]
    ([ModuleName],[SchemaName],[TableName],[VisualCode],[IsActive],[UpdatedBy])
VALUES
    ('{ModuleName}','accoTOOL${ModuleName}','{TableName}','{AP|AM|AC}',1,'{your identity}');
```

⚠️ A v1.0-documented auto-population procedure (`sp_work_RefreshWritebackConfig`, scanning `sys.tables` and joining to a `Config_Modules` table) is intentionally **not** included here. It doesn't exist anywhere in any database this project has actually built against, its dependency (`Config_Modules`) doesn't exist either, and every real `Config_Writeback` row observed was inserted by hand. Leave it out unless it's specifically reintroduced later with confirmation that it's actually wanted.

### 4.3 Log_Audit 🟢 single shared table, matches the framework's mandatory column list exactly

**One shared audit table for the whole database**, not one per module. Every writeback event from accoMASTERDATA or accoCOMMENT logs here.

```sql
CREATE TABLE [accoTOOL$Base].[Log_Audit] (
    [LogKey]          INT IDENTITY(1,1) NOT NULL,
    [RowKey]          NVARCHAR(100)  NOT NULL,   -- the audited row's business-key value, as text
    [TransactionType] NVARCHAR(100)  NOT NULL,   -- requires the writeback tool's audit-type mapping to be configured
    [SQLCommand]      NVARCHAR(4000) NOT NULL,
    [UpdatedBy]       NVARCHAR(200)  NOT NULL,
    [UpdateDateTime]  DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Log_Audit PRIMARY KEY ([LogKey])
);
CREATE NONCLUSTERED INDEX IX_Log_Audit_UpdatedBy_UpdateDateTime ON [accoTOOL$Base].[Log_Audit] ([UpdatedBy],[UpdateDateTime]);
```

🟢 **Column set matches the accoTOOL Solution Framework Documentation §4.3 "Mandatory Columns – Audit Log" exactly**: `UpdatedBy`, `UpdateDateTime`, `RowKey`, `TransactionType`, `SQLCommand`. `LogKey` is the only addition, a surrogate PK — a technical necessity the framework doesn't preclude, not a substantive column.

⚠️ **No source/module differentiator column.** Because this table is shared across every module, a row alone doesn't say which module or table it came from — only `RowKey` (the audited row's own key, as text) and whatever the connected writeback identity/timestamp narrow it down to. An earlier version of this table added `ModuleName`/`SchemaName`/`TableName` columns to solve this, which was a mistake: those columns aren't in the framework's mandatory list, they were never verified against it, and accoMASTERDATA has no property that can populate arbitrary extra `NOT NULL` columns on its audit target — every writeback would have failed the constraint. Corrected back to the framework's exact column set. If cross-module identification of audit rows is genuinely needed later, that has to be solved without adding columns the visual can't populate — surface it as a discovery question rather than reintroducing this.

🟡 **`RowKey` is `NOT NULL` — working assumption, pending independent confirmation.** `RowKey` stands in for the audited row's own identity column (e.g. `BK_Employee#ID`), always populated as text. Since a dimension row's identity column is itself never nullable, its text mirror in the audit log shouldn't be either — but this hasn't been independently re-verified against a live accoMASTERDATA write yet in this exact shared-table shape. Treat as the current standard; revisit if a real writeback throws a `NOT NULL` violation on this column.

**Grant `INSERT` on this specific object only** (§8) — never schema-wide on `accoTOOL$Base`, since that schema also holds `Config_Connection`'s plaintext password and the writeback identity should never be able to write there.

### 4.4 Dim_Version#AM — optional, build only when needed

🟢 If a module needs multiple concurrent planning scenarios (e.g. "Budget 2026" vs. "Forecast Q3"), the version dimension belongs in the **shared base schema**, not the module schema — a scenario concept spans modules. Do not build this by default; only when discovery (§2.1, question 4) calls for it.

```sql
CREATE TABLE [accoTOOL$Base].[Dim_Version#AM] (
    [BK_Version#ID]      INT IDENTITY(1,1) NOT NULL,
    [VersionName]        NVARCHAR(200)     NOT NULL,
    [VersionDescription] NVARCHAR(500)     NULL,
    [IsActive]           BIT               NOT NULL DEFAULT 1,
    [UpdatedBy]          NVARCHAR(200)     NOT NULL,
    [CreateDateTime]     DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
    [UpdateDateTime]     DATETIME2(3)      NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_Dim_Version#AM] PRIMARY KEY ([BK_Version#ID])
);
```

⚠️ Version-copy automation (copying one scenario's data into a new one) is a real, vendor-documented concept but has no confirmed, deployed implementation anywhere in this project yet. If a module needs it, design the copy procedure for that module specifically rather than assuming a generic one exists — ask before inventing one from scratch.

---

## 5. Module Schema — Pattern A: Dimension Writeback (accoMASTERDATA)

```sql
CREATE SCHEMA [accoTOOL${ModuleName}];
```

### 5.1 Dimension table

```sql
CREATE TABLE [accoTOOL${ModuleName}].[Dim_{Name}#AM] (
    [BK_{Name}#ID]   INT IDENTITY(1,1) NOT NULL,
    -- domain columns here
    [IsActive]       BIT               NOT NULL DEFAULT (1),
    [UpdatedBy]      NVARCHAR(200)     NOT NULL,
    [CreateDateTime] DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME()),
    [UpdateDateTime] DATETIME2(3)      NOT NULL DEFAULT (SYSUTCDATETIME()),
    CONSTRAINT [PK_Dim_{Name}#AM] PRIMARY KEY ([BK_{Name}#ID])
);
CREATE NONCLUSTERED INDEX [IX_Dim_{Name}#AM_UpdatedBy] ON [accoTOOL${ModuleName}].[Dim_{Name}#AM] ([UpdatedBy],[UpdateDateTime]);
-- plus one index per business-key/lookup column actually queried
```

🟢 **Self-referencing hierarchy columns are valid** — apply `FBK_{DimName}#{Col}` reflexively, e.g. a Manager relationship on an Employee dimension:

```sql
[FBK_{Name}#ID] INT NULL,  -- e.g. FBK_Employee#ID for a Manager reference
CONSTRAINT [FK_Dim_{Name}_Self] FOREIGN KEY ([FBK_{Name}#ID]) REFERENCES [accoTOOL${ModuleName}].[Dim_{Name}#AM]([BK_{Name}#ID])
```
Nullable, since the top of any hierarchy has no parent.

There is no module-level audit table in this pattern — writeback events for this table log to the single shared `accoTOOL$Base.Log_Audit` (§4.3).

### 5.2 Module view

```sql
CREATE VIEW [accoTOOL${ModuleName}].[vw_Dim_{Name}] AS
SELECT
    [BK_{Name}#ID],
    -- domain columns,
    -- for any open-ended date column, apply the sentinel pattern (§3.1)
    [IsActive], [UpdatedBy], [CreateDateTime], [UpdateDateTime]
FROM [accoTOOL${ModuleName}].[Dim_{Name}#AM]
WHERE [IsActive] = 1;
```

---

## 6. Module Schema — Pattern B: Fact Writeback (accoPLANNING)

### 6.1 Normal fact (append-only, no aggregation needed)

```sql
CREATE TABLE [accoTOOL${ModuleName}].[Fact_{Name}#AP] (
    [FactKey]        BIGINT IDENTITY(1,1) NOT NULL,
    [FBK_{Dim}#ID]   INT           NOT NULL,   -- one FBK per referenced dimension
    [FBK_Version#ID] INT           NULL,       -- only if Dim_Version#AM (§4.4) is in use
    -- measure columns (writable in accoPLANNING)
    [UpdatedBy]      NVARCHAR(200) NOT NULL,
    [UpdateDateTime] DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_Fact_{Name}#AP] PRIMARY KEY ([FactKey])
);
-- index every FBK column and (UpdatedBy, UpdateDateTime)
```

### 6.2 RAW → Current → trigger (when inputs need aggregating before display)

**Why this pattern, not a single table:** accoPLANNING can send delta values on each write rather than the final absolute number, depending on configuration. Without a merge step you'd need complex downstream logic to sum deltas correctly every time. The Current table always holds the clean, current value; the RAW table keeps full write history.

⚠️ **The merge's aggregation is not a template detail — it must match the write mode the visual is configured for, and the two modes need different aggregations.** This is a cross-layer decision (see `accotool-ai-solution-planning`'s [`references/accotool-ai-cross-layer-contracts.md`](../../../accotool-ai-solution-planning/accotool-ai-solution-planning/references/accotool-ai-cross-layer-contracts.md) C8): the visual's shadow-calculation delta setting is owned by `accotool-ai-customvisual-accoplanning` §5, and this trigger is where that setting becomes a correctness property of the stored data.

| accoPLANNING write mode | Correct aggregation over the RAW history for one key | Why |
|---|---|---|
| **Delta** (the "Calculate delta for shadow calculations" behaviour, AP §5) | `SUM([Measure])` | 🟢 Confirmed in AP §5: three accumulated rows reading *(blank)* / `10` / `-7` are correct only when summed. Each row is a change, not a state |
| **Absolute** (each write sends the final value) | latest non-`NULL` by `UpdateDateTime` — e.g. `MAX(CASE WHEN [Measure] IS NOT NULL THEN [UpdateDateTime] END)` resolved back to its value, or a `ROW_NUMBER()`/`OUTER APPLY` per key | the newest write wins; earlier ones are superseded |

**`MAX([Measure])` is correct in neither mode** — it picks the largest value ever written, which coincides with the right answer only while values happen to increase. It fails silently: the table fills with plausible numbers that are simply wrong, and nothing errors. The illustrative `MAX(CASE WHEN ... END)` in the template below is a placeholder for "one expression per measure", not a recommendation — replace it with the row from the table above before deploying.

Note that the merge deliberately recomputes from the **full RAW history** for the affected keys rather than from `inserted` alone. That is what makes both modes correct — a delta sum needs every prior row, and a latest-wins resolution needs to know what it is superseding.

```sql
-- History fact — writeback target, append-only
CREATE TABLE [accoTOOL${ModuleName}].[Fact_{Name}_RAW#AP] (
    [FactKey]        BIGINT IDENTITY(1,1) NOT NULL,
    [FBK_{Dim}#ID]   INT           NOT NULL,
    [FBK_Version#ID] INT           NULL,
    -- measure columns
    [UpdatedBy]      NVARCHAR(200) NOT NULL,
    [UpdateDateTime] DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_Fact_{Name}_RAW#AP] PRIMARY KEY ([FactKey])
);

-- Current fact — cleansed/aggregated, maintained by trigger, NOT a writeback target itself
CREATE TABLE [accoTOOL${ModuleName}].[Fact_{Name}_Current] (
    [FactKey]        BIGINT IDENTITY(1,1) NOT NULL,
    [FBK_{Dim}#ID]   INT           NOT NULL,
    [FBK_Version#ID] INT           NULL,
    -- measure columns
    [UpdatedBy]      NVARCHAR(200) NOT NULL,
    [UpdateDateTime] DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT PK_Fact_{Name}_Current PRIMARY KEY ([FactKey])
);
CREATE UNIQUE INDEX UX_Fact_{Name}_Current_Keys
    ON [accoTOOL${ModuleName}].[Fact_{Name}_Current] ([FBK_{Dim}#ID],[FBK_Version#ID]);

-- Trigger: COALESCE merge so a NULL delta never erases a stored value
CREATE OR ALTER TRIGGER [accoTOOL${ModuleName}].[TR_Fact_{Name}_RAW#AP_After_Insert_MergeToCurrent]
ON [accoTOOL${ModuleName}].[Fact_{Name}_RAW#AP]
AFTER INSERT
AS
BEGIN
    SET NOCOUNT ON;
    MERGE [accoTOOL${ModuleName}].[Fact_{Name}_Current] AS target
    USING (
        SELECT [FBK_{Dim}#ID], [FBK_Version#ID],
               /* one expression per measure -- SUM for delta writes, latest-non-NULL-by-UpdateDateTime
                  for absolute writes. See the aggregation table above; MAX of the value is wrong in both. */
               MAX([UpdatedBy]) AS [UpdatedBy], MAX([UpdateDateTime]) AS [UpdateDateTime]
        FROM [accoTOOL${ModuleName}].[Fact_{Name}_RAW#AP]
        WHERE [FBK_{Dim}#ID] IN (SELECT [FBK_{Dim}#ID] FROM inserted)
        GROUP BY [FBK_{Dim}#ID],[FBK_Version#ID]
    ) AS source
    ON (target.[FBK_{Dim}#ID] = source.[FBK_{Dim}#ID] AND target.[FBK_Version#ID] = source.[FBK_Version#ID])
    WHEN MATCHED THEN
        UPDATE SET /* [Measure] = COALESCE(source.[Measure], target.[Measure]), one per measure */
            [UpdatedBy] = source.[UpdatedBy], [UpdateDateTime] = source.[UpdateDateTime]
    WHEN NOT MATCHED THEN
        INSERT ([FBK_{Dim}#ID],[FBK_Version#ID], /* measures, */ [UpdatedBy],[UpdateDateTime])
        VALUES (source.[FBK_{Dim}#ID],source.[FBK_Version#ID], /* measures, */ source.[UpdatedBy],source.[UpdateDateTime]);
END;
```

### 6.3 Module engine view

```sql
CREATE VIEW [accoTOOL${ModuleName}].[vw_Fact_{Name}] AS
SELECT /* joined output combining Fact_{Name}_Current with warehouse/reference tables as needed */
FROM [accoTOOL${ModuleName}].[Fact_{Name}_Current] c;
```

### 6.4 Optional: accoPLANNING's built-in comment column (alternative to Pattern C)

🟡 Per the organization's own accoPLANNING documentation, not yet tested in this project. accoPLANNING has its own built-in comment feature, entirely separate from the standalone accoCOMMENT visual (Pattern C, §7). It's often the simpler choice when a comment just needs to travel alongside a specific measure being planned, rather than needing its own independently governed audit object.

**What it needs at the database layer — and nothing more:**

```sql
ALTER TABLE [accoTOOL${ModuleName}].[Fact_{Name}#AP]  -- or Fact_{Name}_RAW#AP
ADD [Comment] NVARCHAR(4000) NULL;
```

No separate table and no separate audit log — the comment lives directly on the fact row being planned. Everything else (which measure it attaches to, how multiple comments combine, how history displays) is resolved by the writeback tool and downstream DAX, not by additional schema.

**Naming convention that matters here:** the column name must match the name of at least one of the comment measures bound to it in the visual — the same measure-name-equals-column-name pattern used elsewhere in this framework. Only one measure needs to match; if multiple comment measures are configured, the tool combines them into that single column.

⚠️ **Multiple comments can be combined into one stored value using a delimiter** (e.g. `Quantity>>test1|Price>>test2`) when "separate comment per measure" is enabled, for up to three comment measures. A `Comment` column used this way can hold more than one free-text comment at once — size it with that in mind, not just for a single comment's expected length.

🟡 **Comment history is reconstructed at query time from an append-only fact, not by growing a single stored value.** The source documentation's "audit trail of comments" display is built via DAX aggregating (`CONCATENATEX`/`LASTNONBLANK`) over every row of an append-only writeback fact table, ordered by `UpdateDateTime` — the same append-only pattern already used in §6.1/§6.2, not a field that gets appended to indefinitely. This is a different table from Pattern C's `Fact_{Name}_Comment#AC` and does not resolve the open overflow question flagged in §7 — that concern is about the standalone accoCOMMENT table specifically, not this one.

How the comment is displayed, submitted, or configured in the visual (dialog boxes, save-vs-commit behavior, DAX measures for date/user enrichment) is semantic-model/visual territory — out of scope here.

### 6.5 Optional: cell-locking support

🟡 Per the organization's own accoPLANNING documentation, not yet tested in this project. accoPLANNING can lock individual cells against writeback based on a measure that returns `1` (locked) or `0` (open) per cell. Whether this needs anything at the database layer depends entirely on where that measure's logic comes from:

- **Pure DAX logic with no stored state** (e.g. "lock every cell before the current calendar month") — no database changes needed. Out of scope for this skill.
- **Version-boundary locking** — if which months are locked depends on the selected planning version (e.g. a "Forecast 6+6" version only allows entry from July onward; earlier months are locked and show realized actuals instead), add a boundary column to `Dim_Version#AM` (§4.4):

```sql
ALTER TABLE [accoTOOL$Base].[Dim_Version#AM]
ADD [OpenFromMonth] INT NULL;  -- 1-12; months before this value are locked for entry, per the selected version
```

  This is a real, named technique confirmed by the organization's own documentation (add an extra column to the version dimension defining the open/locked boundary) — not a speculative addition.

- **User-toggled or organizational locking** — when users can lock/unlock cells directly (e.g. right-click in the grid) and that state must persist, it needs a dedicated writeback table. Model it as an append-only event log, not a mutable current-state table — each lock/unlock action is a new row, and a view resolves the latest state per key:

```sql
CREATE TABLE [accoTOOL${ModuleName}].[Fact_{Name}_CellLock#AP] (
    [FactKey]        BIGINT IDENTITY(1,1) NOT NULL,
    [FBK_{Dim}#ID]   INT           NOT NULL,   -- one FBK per dimension the lock applies to (e.g. organization) — add further key columns to match the actual grain (e.g. a period key)
    [FBK_Version#ID] INT           NULL,
    [LockState]      INT           NOT NULL,   -- 1 = locked, 0 = unlocked
    [UpdatedBy]      NVARCHAR(200) NOT NULL,
    [UpdateDateTime] DATETIME2(3)  NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_Fact_{Name}_CellLock#AP] PRIMARY KEY ([FactKey])
);

CREATE VIEW [accoTOOL${ModuleName}].[vw_Fact_{Name}_CellLock] AS
WITH _Latest AS (
    SELECT t.*
    FROM [accoTOOL${ModuleName}].[Fact_{Name}_CellLock#AP] t
    WHERE t.[UpdateDateTime] IN (
        SELECT MAX(t2.[UpdateDateTime])
        FROM [accoTOOL${ModuleName}].[Fact_{Name}_CellLock#AP] t2
        WHERE t2.[FBK_{Dim}#ID] = t.[FBK_{Dim}#ID] AND t2.[FBK_Version#ID] = t.[FBK_Version#ID]
        GROUP BY t2.[FBK_{Dim}#ID], t2.[FBK_Version#ID]
    )
)
SELECT [FBK_{Dim}#ID], [FBK_Version#ID], [LockState]
FROM _Latest
WHERE [LockState] = 1;
```

  ⚠️ The source documentation for this pattern uses its own literal example names (an `accoPLANNING` schema, a `Writeback_Planning_CellLock` table) that do **not** follow this project's `accoTOOL$ModuleName`/`Fact_{Name}#{Visual}` naming convention. The SQL above is the same underlying mechanism — an append-only lock log plus a latest-state view — translated into this project's actual naming standard. Do not copy the source's literal names.

  Same naming rule as everywhere else: the writeback table needs a column matching the name of whichever measure is placed in the visual's Cell Lock area.

Which of these approaches, if any, is needed is a discovery-conversation decision (§2.1) — do not default to building a dedicated lock table when version-boundary locking alone would answer the business need.

---

## 7. Module Schema — Pattern C: Comment Writeback (accoCOMMENT)

```sql
CREATE TABLE [accoTOOL${ModuleName}].[Fact_{Name}_Comment#AC] (
    [CommentKey]     BIGINT IDENTITY(1,1) NOT NULL,
    [FBK_{Dim}#ID]   INT            NOT NULL,
    [FBK_Version#ID] INT            NULL,
    [Comment]        NVARCHAR(4000) NULL,
    [UpdatedBy]      NVARCHAR(200)  NOT NULL,
    [UpdateDateTime] DATETIME2(3)   NOT NULL DEFAULT SYSUTCDATETIME(),
    CONSTRAINT [PK_Fact_{Name}_Comment#AC] PRIMARY KEY ([CommentKey])
);
```

⚠️ **Known open issue — inherited, not independently verified:** if comment history accumulates by appending into a single field over time, repeated edits can overflow `NVARCHAR(4000)`. This claim traces back to an external reference ("Accobat's KB") cited in this project's prior documentation, not to anything tested in this project. No cleanup approach has ever been captured here. Flag as an open item if a comment table is expected to see heavy repeated editing on the same cell, and treat the underlying claim itself as unconfirmed until someone actually reproduces it.

---

## 8. Writeback Identity Provisioning (Single Shared User & Role)

🟢 **There is one writeback SQL user and one writeback role per database, shared by every module.** This corrects the v1.0 skill, which specified one dedicated user/role *per module* — that was never actually how any real deployment in this project works, and has been explicitly confirmed as the wrong standard.

### 8.1 Check before creating anything

```sql
-- Source of truth: does a shared connection already exist?
SELECT * FROM [accoTOOL$Base].[Config_Connection];
```

If a row exists, confirm its `DBUser` is a real, current principal:

```sql
SELECT name, type_desc FROM sys.database_principals WHERE name = '{DBUser from Config_Connection}';
```

If both check out, **reuse that identity** — skip straight to §8.3 (grants) for any new schema this build introduces. Do not create a second identity.

If `Config_Connection` is empty, also check for a principal matching this project's naming convention before assuming a fresh install:

```sql
SELECT name, type_desc FROM sys.database_principals WHERE name = 'writeback_user';
```

### 8.2 If nothing exists — provision fresh

🟢 **Claude Code creates this directly via the SQL MCP** — this is a deliberate, explicit decision for this project, overturning the earlier standing rule that credential creation must be a manual, human-run step. Do not revert to asking a human to run this manually unless told to.

Use `writeback_user` / `writeback_role` as the standard names — meaningful, and consistent with every existing deployment in this project. Generate a strong password: minimum 24 characters, mixing uppercase, lowercase, digits, and symbols, avoiding `'`, `]`, and `--` so it stays a safe T-SQL string literal. Never reuse a password across environments, and don't echo it back in conversation once stored — it lives in `Config_Connection` and nowhere else.

```sql
CREATE USER [writeback_user] WITH PASSWORD = '{generated strong password}';
CREATE ROLE [writeback_role];
ALTER ROLE [writeback_role] ADD MEMBER [writeback_user];

-- Baseline grants every shared identity needs regardless of which modules exist yet
GRANT SELECT ON SCHEMA::[accoTOOL$Base] TO [writeback_role];
GRANT INSERT ON OBJECT::[accoTOOL$Base].[Log_Audit] TO [writeback_role];  -- object-level only, never schema-wide

-- Verify
SELECT name, type_desc FROM sys.database_principals WHERE name IN ('writeback_user','writeback_role');
```

Then populate `Config_Connection` with the single row (§4.1):

```sql
INSERT INTO [accoTOOL$Base].[Config_Connection]
    ([ServerName],[DatabaseName],[AuthMethod],[DBUser],[DBPassword],[UpdatedBy])
VALUES
    ('{server}.database.windows.net','{database}','SQLUser','writeback_user','{generated strong password}','{your identity}');
```

### 8.3 Extending grants for a new module (every build, whether the identity is new or reused)

```sql
GRANT SELECT, INSERT, UPDATE, DELETE, VIEW DEFINITION ON SCHEMA::[accoTOOL${ModuleName}] TO [writeback_role];
GRANT SELECT, VIEW DEFINITION ON SCHEMA::[dmAccoTOOL_{Name}] TO [writeback_role];
```

Schema-wide grants cover every table/view added to that schema later, including a Pattern B `Fact_{Name}_Current` table — no separate per-table grant is needed.

---

## 9. Datamart Schema (`dmAccoTOOL_{Name}`)

🟢 **Naming rules (critical — names must match exactly whatever downstream consumer reads them, but what that consumer is or how it reads them is out of scope here):**

| Object type | Pattern | Example |
|---|---|---|
| Fact | `_{Name}` (leading underscore) | `_SalaryPlan` |
| Dimension | `{Name}` (no prefix) | `Employee` |
| Config/metadata | `Config_{Name}` | `Config_Writeback` |

```sql
CREATE VIEW [dmAccoTOOL_{Name}].[_{FactName}] AS
SELECT c.[FBK_{Dim}#ID], /* measures */, c.[UpdatedBy], c.[UpdateDateTime]
FROM [accoTOOL${ModuleName}].[Fact_{Name}_Current] c;

CREATE VIEW [dmAccoTOOL_{Name}].[{DimName}] AS
SELECT d.[BK_{Name}#ID], /* domain columns */
FROM [accoTOOL${ModuleName}].[vw_Dim_{Name}] d;

CREATE VIEW [dmAccoTOOL_{Name}].[Config_Writeback] AS
SELECT [ModuleName],[SchemaName],[TableName],[VisualCode]
FROM [accoTOOL$Base].[Config_Writeback]
WHERE [ModuleName] = '{ModuleName}' AND [IsActive] = 1;

CREATE VIEW [dmAccoTOOL_{Name}].[Config_Connection] AS
SELECT [ServerName],[DatabaseName],[AuthMethod],[DBUser],[DBPassword]
FROM [accoTOOL$Base].[Config_Connection]
WHERE [DBUser] = 'writeback_user';
```

⚠️ Exposing `DBPassword` in this view means anyone who can query it can read the credential in plaintext. Accepted for PoC/demo with a least-privilege writeback identity (§4.1); a deliberate call to revisit for production. How this view gets consumed downstream — DAX, visual property binding, storage mode — is explicitly out of scope for this skill.

---

## 10. Altering Existing Objects

Everything in §5–§7 covers *creating* new objects. This section is the missing counterpart: safely changing an object that already exists and may already hold real data — a different risk profile, since a `CREATE` can only ever add something new, while these operations can break a dependent or destroy data if done carelessly.

### 10.1 Pre-alteration discovery (mandatory before any ALTER)

Before touching an existing object, establish its current shape and everything that depends on it. Do not assume it still matches whatever the original build template said — real deployments drift.

```sql
-- Current column shape
SELECT COLUMN_NAME, DATA_TYPE, IS_NULLABLE, COLUMN_DEFAULT
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = '{schema}' AND TABLE_NAME = '{table}';

-- Everything that references this object (views, triggers, procedures)
SELECT DISTINCT
    OBJECT_SCHEMA_NAME(d.referencing_id) AS referencing_schema,
    OBJECT_NAME(d.referencing_id)        AS referencing_object,
    o.type_desc
FROM sys.sql_expression_dependencies d
JOIN sys.objects o ON o.object_id = d.referencing_id
WHERE d.referenced_id = OBJECT_ID('{schema}.{table}');

-- Does the table already hold data? (drives whether §10.5's caution applies)
SELECT COUNT(*) FROM [{schema}].[{table}];
```

Do not proceed until you know: current column shape, every direct dependent, and whether the table is empty or populated.

### 10.2 Adding a column to an existing writeback table

Low-risk to the base table itself, but this framework specifically creates a ripple effect that's easy to miss.

```sql
-- Safe add: nullable, or NOT NULL with a DEFAULT so existing rows don't break
ALTER TABLE [accoTOOL${ModuleName}].[Dim_{Name}#AM]
ADD [{NewColumn}] {DataType} NULL;

-- or, if it must be required immediately:
ALTER TABLE [accoTOOL${ModuleName}].[Dim_{Name}#AM]
ADD [{NewColumn}] {DataType} NOT NULL
    CONSTRAINT [DF_{Table}_{NewColumn}] DEFAULT ({DefaultExpression});
```

⚠️ **The new column does not appear anywhere downstream automatically.** Every view in this skill — `vw_Dim_{Name}`, and each datamart view — is written with an explicit column list, never `SELECT *`. Adding the column to the base table is only step one:

```sql
ALTER VIEW [accoTOOL${ModuleName}].[vw_Dim_{Name}] AS
SELECT
    [BK_{Name}#ID],
    -- existing domain columns,
    [{NewColumn}],   -- <-- added
    [IsActive], [UpdatedBy], [CreateDateTime], [UpdateDateTime]
FROM [accoTOOL${ModuleName}].[Dim_{Name}#AM]
WHERE [IsActive] = 1;

ALTER VIEW [dmAccoTOOL_{Name}].[{DimName}] AS
SELECT
    d.[BK_{Name}#ID],
    -- existing domain columns,
    d.[{NewColumn}],   -- <-- added
    d.[IsActive], d.[UpdatedBy], d.[CreateDateTime], d.[UpdateDateTime]
FROM [accoTOOL${ModuleName}].[vw_Dim_{Name}] d;
```

Without updating both, the new attribute is invisible past the base table. No grant changes are needed — column-level access is already covered by the schema-wide `GRANT` the table's schema received in §8.3.

### 10.3 Adding a new table to an already-existing module schema

If `accoTOOL${ModuleName}` already exists (a second dimension, a second fact, an accoCOMMENT table added to an established module), skip `CREATE SCHEMA` — build the new table using the normal pattern (§5–§7). The schema-level `GRANT` issued when the module schema was first created (§8.3) already covers any object added to that schema later; no additional grant statement is needed.

Still register the new table in `Config_Writeback` (§4.2) — that's a per-table row, not a per-schema one, so it does not happen automatically just because the schema itself is already provisioned.

### 10.4 Changing a column's type or nullability on a populated table

Tightening a constraint on a table that already has rows can fail outright, or — worse — succeed while corrupting data.

**Adding `NOT NULL` to a currently-nullable column** — confirm no existing row has `NULL` there first; the `ALTER` fails immediately otherwise:

```sql
SELECT COUNT(*) FROM [{schema}].[{table}] WHERE [{Column}] IS NULL;
-- if > 0, backfill before altering:
UPDATE [{schema}].[{table}] SET [{Column}] = {BackfillValue} WHERE [{Column}] IS NULL;
```

**Narrowing a data type** (e.g. `NVARCHAR(200)` → `NVARCHAR(50)`, `INT` → `SMALLINT`) — confirm no existing value would be truncated or overflow. SQL Server refuses some truncating changes outright, but not all — check rather than relying on it to fail safely:

```sql
SELECT * FROM [{schema}].[{table}] WHERE LEN([{Column}]) > {NewLength}; -- example for a narrowing NVARCHAR change
```

Always re-run the §10.1 dependents check afterward — a dependent view can be left silently stale (SQL Server does not automatically re-validate a view's column metadata just because a base table changed).

### 10.5 Standing caution for this whole section

Every operation above touches an object that may already hold real data, or may already be relied on by something downstream — a fundamentally different risk profile from the `CREATE` statements that make up the rest of this skill, which only ever build something new.

**Before running any `ALTER` or `UPDATE` against an object that already has rows in it, confirm the exact statement with the user first — do not treat it as a routine build step the way a fresh `CREATE TABLE` is.** State what will change, what depends on it (from §10.1), and what happens to existing data, then wait for an explicit go-ahead before executing.

---

## 11. Seed / Demo Data

An empty writeback table produces an empty demo. Minimum viable seed, in dependency order:

1. If `Dim_Version#AM` (§4.4) is in use, at least one active version row.
2. Dimension master data — direct `INSERT` into `Dim_{Name}#AM` is fine for initial seeding (bypassing the writeback tool), as long as `UpdatedBy`/`UpdateDateTime` are populated (e.g. `'System'` / `SYSUTCDATETIME()`).
3. Initial fact data, if the demo should show non-empty numbers immediately rather than requiring live data entry first.

No general-purpose seed script exists in this project — design it per module against what that specific demo needs to show.

---

## 12. Verification Checklist

| Check | How |
|---|---|
| Schemas created | `SELECT name FROM sys.schemas WHERE name LIKE 'accoTOOL%' OR name LIKE 'dmAccoTOOL%'` |
| Exactly one shared connection | `SELECT COUNT(*) FROM [accoTOOL$Base].[Config_Connection]` — expect 1 |
| Writeback config populated | `SELECT * FROM [accoTOOL$Base].[Config_Writeback] WHERE ModuleName = '{ModuleName}'` |
| Shared audit log exists | `SELECT * FROM [accoTOOL$Base].[Log_Audit]` (schema check if freshly created; empty is fine) |
| Writeback identity correct | `SELECT name, type_desc FROM sys.database_principals WHERE name IN ('writeback_user','writeback_role')` |
| Role has the grants it needs | Query `sys.database_permissions` joined to `sys.schemas`/`sys.objects` for `writeback_role` — compare against §8.2/§8.3 |
| No cross-module references | Code review: no object in `accoTOOL$X` references `accoTOOL$Y` |
| Datamart views resolve | `SELECT TOP 10 * FROM [dmAccoTOOL_{Name}].[{View}]` for each view created |
| Seed data present (fresh builds) | Datamart dimension/fact views return non-empty rows |

