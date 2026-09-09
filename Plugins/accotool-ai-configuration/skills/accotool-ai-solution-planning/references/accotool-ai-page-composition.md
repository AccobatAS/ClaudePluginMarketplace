# accoTOOL Page Composition — Designing the Report as an Application

The writeback chain is a loop, and **the page is where it closes**. Everything the other skills build — the table, the view, the storage mode, the bound property — exists so that a business user can look at a question, answer it by typing, and immediately see what their answer did. That last step happens on one report page or it doesn't happen at all.

This file owns the accoTOOL-specific part of that page: which visuals have to sit next to the input surface and why, how filter context is shared between them (which is a *correctness* concern here, not a layout preference), and what a user actually sees after a write lands.

**What this file does not own:** how to build an ordinary Power BI visual, choose a chart type, apply a theme, or lay out a canvas. That is generic report authoring — defer to the Microsoft `powerbi-report-design` and `powerbi-report-authoring` skills. This file says what the page must *do*; those say how to build it.

**Confidence markers:**
🟢 Confirmed · 🟡 Working baseline or reasoned from a confirmed mechanism, not independently tested · ⚠️ Open

---

## 1. The three jobs every accoTOOL page has to do

A writeback report is an application. The goal is almost never to capture the data — it is to make a decision safely. That decomposes into three jobs, and a page missing any one of them is unfinished:

| Job | What carries it | Failure mode when it's missing |
|---|---|---|
| **Answer** — what does the user need to know before they can responsibly type anything? | ordinary Power BI visuals: actuals, prior version, run rate, trend, benchmark | the user guesses, or leaves to check elsewhere and doesn't come back |
| **Act** — where the decision gets entered | the accoTOOL visual | there is no application, only a report |
| **Confirm** — what did that entry just do? | a variance/total/coverage visual reading the same writeback data back through the model | the user can't tell a successful write from a silent failure, and doesn't trust the tool |

**A page holding only an accoTOOL grid has one of three jobs.** That isn't a minimal viable page — it usually means the business problem hasn't been articulated yet. Go back to `accotool-ai-solution-planning` Step 6 rather than shipping it.

The *Confirm* job is the one most often skipped, and it is the one that makes the loop visible. It is also close to free: it reads the same datamart fact the grid writes into, through the model that already exists.

---

## 2. Filter context is shared — and for accoPLANNING it is load-bearing on the write

On an ordinary report page, slicers are a convenience. On an accoTOOL page they are part of the write path, because the visual resolves *what to write* out of the same filter context that decides *what to show*.

🟢 accoPLANNING resolves a surrogate foreign key through a `Transaction`-role measure — typically `SELECTEDVALUE` against the dimension's key column — and that works because the visual's own Row/Column filter context already narrows the dimension to exactly one row for the cell being written (`accotool-ai-customvisual-accoplanning` §3).

🟡 **The consequence for page design:** a dimension whose key must be written but which is *not* on an axis has nothing narrowing it except the page's slicers. A planning version is the classic case — it belongs on a slicer, not an axis, yet its key still has to be written on every row. If that slicer allows multi-select, or has no selection, `SELECTEDVALUE` returns blank and the write fails with the same `Cannot insert the value NULL` error as a missing `Transaction` entry — but caused by a slicer, not by the binding.

**So, as page-design rules:**
- Any slicer that scopes a dimension whose key gets written must be **single-select**, and should have a default selection so the page is never in an unwritable state on open.
- Distinguish the two kinds of slicer explicitly when specifying the page: *write-scoping* slicers (version, scenario, organisation — they determine what gets written) and *view-scoping* slicers (they only filter what's displayed). Only the first kind carries this constraint.
- Record which is which in the module's entry in [`accotool-ai-solution-architecture.md`](accotool-ai-solution-architecture.md). It is invisible in the finished file and expensive to rediscover.

⚠️ Not yet tested: whether a *sync'd* slicer across pages, or a slicer whose selection is restored by a bookmark, behaves identically for key resolution. Assume it does, verify before relying on it.

---

## 3. What the user sees after a write

🟢 The mechanism underneath is sound and deliberate: writeback fact views are DirectQuery specifically so current state is read live with no refresh lag (`accotool-ai-semantic-model` §2), and in Pattern B the RAW→Current trigger fires on insert (`accotool-ai-sql-schema` §6.2), so the merged value is queryable the instant the write commits.

⚠️ **What is not established is whether the other visuals on the page re-query on their own after that write.** The data being *available* and a neighbouring visual *choosing to fetch it* are different things, and nothing in this project has tested the second. Treat it as an open question per build rather than an assumption in either direction:

- Verify it directly the first time a page is assembled — edit a cell, save, and watch whether the confirmation visual moves without any other interaction.
- If it does not, the page needs an explicit way to re-query. Options worth testing, in rough order of least intrusive: any refresh affordance the accoTOOL visual itself offers; a slicer or bookmark interaction the user would perform anyway; a report-level refresh control. Pick one and specify it — don't leave the user to discover that the page lies until they click something.
- Whichever way it resolves, record the finding for that build. This is exactly the kind of fact that is expensive to rediscover and cheap to write down.

**Design implication either way:** the *Confirm* visual (§1) should be positioned where the user's eye already is after typing — adjacent to the grid, not below the fold — so a stale value is noticed immediately rather than trusted silently.

---

## 4. Visual interactions between context and input

⚠️ Cross-filtering *into* an accoTOOL visual — a user clicking a bar in a context visual and thereby changing what the grid shows and writes — has not been tested in this project. The risk it carries is real and specific: the same mechanism that makes slicers load-bearing (§2) means an incidental click on a neighbouring chart can silently change the write scope.

Until it is tested, the safe default when specifying a page is to **turn off cross-filtering from context visuals into the accoTOOL visual**, and let deliberate slicers be the only thing that changes its scope. Filtering in the other direction (the grid highlighting context visuals) has no write-path consequence and is a normal design choice.

---

## 5. Two artifacts of the grid worth deciding rather than inheriting

🟢 A dimension view filters `IsActive = 1` (`accotool-ai-sql-schema` §5.2), so a soft-deleted row disappears from every visual on the page at once — expected, but worth saying aloud to a user who wonders where a row went after deleting it in the grid.

🟢 A phantom `(Blank)` member can appear on a Row or Column axis when "show items with no data" is on against a still-sparse writeback fact, and the fix is a per-field report-level filter — each affected axis needs its own (`accotool-ai-customvisual-accoplanning` §2). This is at its worst on a brand-new module's first demo, which is exactly when the page is being shown to someone forming their first impression of it.

🟡 accoPLANNING renders a "Hierarchy" header and automatic Grand Total row and column with no configuration; how to rename or disable them isn't yet explored (AP §7). Decide whether they belong in the story rather than shipping them because they appeared.

---

## 6. Specifying a page — the checklist to hand to report authoring

Produce this before any visual gets built, and record it under **Page compositions** in [`accotool-ai-solution-architecture.md`](accotool-ai-solution-architecture.md):

1. **The business question** this page answers, in one sentence. If it can't be written, the page isn't ready to build.
2. **Answer visuals** — which ones, reading what, and what each contributes to the decision.
3. **The input surface** — which accoTOOL visual, and per `accotool-ai-solution-planning` Step 5, why that one.
4. **The confirm visual** — what the user looks at to see their own edit reflected.
5. **Slicers, split into write-scoping and view-scoping** (§2), with single-select and defaults settled for the first kind.
6. **Interaction settings** — what cross-filters into the grid, if anything (§4).
7. **How a write becomes visible** on this page, and how that was verified (§3).

Steps 1–4 are this skill's judgment. Building them is `powerbi-report-design` / `powerbi-report-authoring`. Steps 5–7 are the accoTOOL-specific constraints those skills have no way to know about — carry them across explicitly rather than assuming a generic report skill will infer them.

---

## 7. Open items for this file

These are unaddressed anywhere in the accoTOOL skill set. Flag them honestly when they come up rather than answering by analogy:

- ⚠️ Whether sibling visuals re-query automatically after a write (§3) — the single most consequential open question here.
- ⚠️ Cross-filtering into an accoTOOL visual (§4).
- ⚠️ **Published behaviour in the Power BI Service.** Everything documented across these skills was verified in Power BI Desktop. Whether writeback works identically once published — gateway requirements for the DirectQuery connection, how the credential bridge behaves under Service-side credential handling, licensing — is untested here. Do not assume a Desktop-verified build is a shipped build.
- ⚠️ **RLS and writeback together.** No skill covers what happens when a row-level-security role filters the fact a user is writing into, or whether the shared writeback identity's grants interact with it. Raise it in discovery for any module with restricted data.
- ⚠️ Multi-user concurrency — two users editing the same cell. The append-only patterns tolerate it structurally, but nothing here defines what either user should *see*.
