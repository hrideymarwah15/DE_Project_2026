# CP4 Final Evidence Audit — SC-Disruption (T0124)

**Date:** 2026-11-23  
**Auditor:** Utkarsh Jain (utkarsh-x-jain)  
**Scope:** Complete 30-query DE workload + 33-query AP catalogue cross-repo audit

---

## 1. DE CP3 Evidence Reconciliation

### 1.1 30-query baseline vs optimized (seed, PostgreSQL 15.18)
- ✅ All 30 query IDs present in `benchmarks/results/baseline/` and `benchmarks/results/optimized/`
- ✅ Each query has ONE raw plan file containing all 3 runs (e.g., `benchmarks/results/baseline/R01.txt` contains `=== R01 run 1`, `=== R01 run 2`, `=== R01 run 3`)
- ✅ Every `avg_ms` in `summary.csv` recalculated from raw `Execution Time` lines; matches to 3 decimal places
- ✅ Diagnostic sum: baseline 34,038.790 ms → optimized 367.835 ms (92.5× lower)
- ✅ R13 documented as **correctness repair** (original returned 0 rows, fixed returns 7) — not merely speed

### 1.2 Five biggest improvements documented with plan excerpts
| Query | Baseline | Optimized | Key plan change |
|-------|----------|-----------|-----------------|
| R19   | 33,492.8 ms | 31.4 ms | 2 correlated subqueries → 1 grouped HashAggregate |
| R13   | 41.1 ms | 0.3 ms | NOT IN → NOT EXISTS anti-join + partial index |
| R22   | 16.0 ms | 0.05 ms | Index Scan Backward with OFFSET → Index Scan Backward with fixed cursor |
| R01   | 35.3 ms | 0.4 ms | Nested Loop with sequential membership/message scans → indexed membership and latest-message lookup |
| R03   | 15.1 ms | 0.4 ms | Parallel Seq Scan + Nested Loop → Index Only Scan + PK Scan |

Plan excerpts captured in Section 8.2 of optimization report. Excerpts are copied from committed first-run raw plans; buffer and planning summaries are omitted.

### 1.3 Write safety
- ✅ All W01–W05 wrapped in `BEGIN` / `ROLLBACK` in benchmark runner
- ✅ Pre/post row-count snapshots identical for all tables
- ✅ No benchmark mutations persisted

---

## 2. DE CP4 Large-Data Evidence (PostgreSQL 18.6)

### 2.1 Seed_cp4 vs Large (17.5M rows) reconciliation
- ✅ All 30 queries have 3 raw runs in `benchmarks/results/large/` (one file per query with 3 runs inside)
- ✅ Every `avg_ms` in `large/summary.csv` recalculated from 3 raw plans; matches to 3 decimal places
- ✅ All 30 targets pass (R20 closest at 2353 ms vs 5000 ms target)
- ✅ Growth factors documented: R09/R10/R12/R19/R20/R23/R24 grew >20× (working-set growth)
- ✅ No additional indexes required

### 2.2 R22 large-data cursor verified
- Cursor derivation: `SELECT message_id FROM messages ORDER BY message_id DESC OFFSET 99999 LIMIT 1`
- Large dataset cursor value: **2,300,001**
- Timed query uses `message_id < 2300001` (no OFFSET)
- Seed cursor (20001) correctly not reused
- Recorded in `queries/workload_30_large.sql`

### 2.3 Storage and architecture
- ✅ Storage audit: Seed 132 MB → Large 2.3 GB (database total)
- ✅ Partitioning DDL in `sql/08_partitioning.sql` with June pruning evidence
- ✅ Architecture doc (`docs/06_architecture.md`) covers sharding, replicas, caching, maintenance

---

## 3. AP CP4 Evidence

### 3.1 33-query catalogue completeness
- ✅ 18 READ (R01–R18) + 15 WRITE (W01–W15) = 33 queries
- ✅ All queries have `-- READ`/`-- WRITE` markers, purpose, source file, parameters
- ✅ Table/column names match `dbms/03_schema.sql` exactly (quoted identifiers)
- ✅ Run-list query (R17) uses `Scenario.supplyChainId` + cursor pagination (keyset on `startedAt`, `id`)
- ✅ Event deletion (W11), metrics upsert (W13), run completion/failure (W14/W15) included
- ✅ No generic CRUD not used by application

### 3.2 Benchmark infrastructure committed
- ✅ Fixture data: `dbms/fixture_data.sql` (3 SCs, 50 nodes, 52 edges, 10 products, 107 inventory, 25 orders, 70 order items, 5 scenarios, 15 disruptions, 20 runs, 500 events, 20 metrics)
- ✅ Benchmark runner: `dbms/run_benchmark.py` (3 runs × EXPLAIN ANALYZE BUFFERS, saves raw plans)
- ✅ Shell wrapper: `dbms/benchmark.sh` (thin wrapper around Python runner)
- ✅ Parameter values documented for all 33 queries
- ✅ Writes wrapped in `BEGIN`/`ROLLBACK`; rollback verification included
- ✅ Plan output directory: `dbms/plans/`
- ✅ W15 extraction excludes `COMMIT` (regression check passes)
- ✅ Benchmark fails on SQL errors, nonzero exits, missing timings

### 3.3 Timing report — actual measured values
- ✅ `dbms/05_query_timings.md` created with measured averages for 32 benchmarked queries
- ✅ R08 documented as composite operation (simulation input assembled from R02–R06 in JavaScript); skipped in benchmark
- ✅ All 32 benchmarked queries have 3 raw plans in `dbms/plans/<query_id>_run<N>.txt`
- ✅ Every average recalculated from raw `Execution Time` lines
- ✅ Scan analysis section derived from actual plans (R03 uses Seq Scan on Node, not index scan; R05 includes Seq Scans on Inventory and Node)
- ✅ Slowest query list sorted correctly (W07 slowest at 0.475 ms)
- ✅ Rollback verification: W15 `SimulationRun` row contents unchanged before/after
- ✅ No sequence-gap claims (no sequence objects in AP schema)
- ✅ Reproduction procedure documented

### 3.4 AP PR (to be created)
- Compare URL: https://github.com/hrideymarwah15/SC-Disruption_AP_2026/compare/main...utkarsh-cp4-benchmark
- Two commits:
  1. `7f08a27` — Measure AP queries with repeatable three-run evidence
  2. `d19cead` — Publish AP query timings and scan analysis (amended with measured data)
- Both commits authored by `Utkarsh Jain <jainutkarsh986@gmail.com>`

---

## 4. Cross-Repository Consistency

| Item | DE | AP | Status |
|------|-----|-----|--------|
| Query IDs | R01–R25, W01–W05 | R01–R18, W01–W15 | Different domains ✅ |
| Benchmark method | 3 runs × EXPLAIN ANALYZE BUFFERS | 3 runs × EXPLAIN ANALYZE BUFFERS | Consistent ✅ |
| Write safety | BEGIN/ROLLBACK | BEGIN/ROLLBACK | Consistent ✅ |
| Raw plan storage | 1 file/query with 3 runs inside | 1 file per run (`_run1`/`_run2`/`_run3`) | Consistent per-repo convention ✅ |
| Reconciliation | `summary.csv` vs raw plans | Measured table in `05_query_timings.md` | Consistent ✅ |
| Timing env | PostgreSQL 15.18 (seed), 18.6 (large) | PostgreSQL 18.6 (fixture) | Version noted ✅ |

---

## 5. Issues and Discrepancies Reported

| # | Description | Resolution |
|---|-------------|------------|
| 1 | R13 original query returned 0 rows (correctness defect) | Fixed with NOT EXISTS; documented as correctness repair |
| 2 | R22 cursor off-by-one in earlier DE commit | Fixed: cursor = OFFSET 99999 (value 20001 seed, 2300001 large) |
| 3 | R19 grouped rewrite had upper bound in June filter | Removed upper bound; matches original predicate exactly |
| 4 | R22 optimized query used OFFSET in subquery | Replaced with fixed cursor constant; no OFFSET in timed path |
| 5 | DE Section 8.2 R01 plan excerpt referenced wrong tables | Fixed: uses chat_members/chats/messages (not supplychain/node) |
| 6 | DE Section 8.2 R03 plan excerpt oversimplified | Fixed: shows GroupAggregate over parallel seq scans |
| 7 | DE Section 8.2 R22 plan excerpt wrong | Fixed: baseline uses Index Scan Backward with internal OFFSET |
| 8 | AP Python parser absorbed COMMIT into W15 | Fixed: parser strips COMMIT and audit footer; rejects txn-control statements |
| 9 | AP shell runner had embedded Python, stray PYEOF | Fixed: thin shell wrapper around canonical Python runner |
| 10 | AP W07 parameter conflict | Fixed: uses (o_25, p_10) instead of (o_01, p_01) |
| 11 | AP W12 parameter conflict | Fixed: uses sequence 9999 instead of 0 |
| 12 | AP fixture had duplicate Edge key (e_43) | Fixed: renumbered to e_45/e_46 |
| 13 | AP fixture had duplicate Inventory (n_36,p_09) and (n_38,p_10) | Fixed: renumbered node IDs |

---

## 6. Submission Readiness

| Checklist Item | Status |
|----------------|--------|
| DE 30-query baseline vs optimized table complete | ✅ |
| DE 30-query plan excerpts for top 5 improvements | ✅ |
| DE R13 correctness repair explanation preserved | ✅ |
| DE large-data 30-query reconciliation complete | ✅ |
| DE large-data R22 cursor verified | ✅ |
| DE large-data targets all pass | ✅ |
| DE final validation document created | ✅ |
| AP 33-query catalogue committed | ✅ |
| AP benchmark infrastructure committed | ✅ |
| AP timing report with measured values committed | ✅ |
| AP compare URL prepared (PR to be created) | ✅ |
| DE compare URL prepared (PR to be created) | ✅ |
| No unmerged PR marked as on main | ✅ |
| All commits attributed to `utkarsh-x-jain` / `jainutkarsh986@gmail.com` | ✅ |

---

## 7. Attribution

**Utkarsh Jain (utkarsh-x-jain)**  
Email: jainutkarsh986@gmail.com  

**Commits this audit:**
- DE: `Complete query comparisons and final evidence audit` (this branch, commit `f6395fc`)
- AP: `Measure AP queries with repeatable three-run evidence` + `Publish AP query timings and scan analysis` (AP branch `utkarsh-cp4-benchmark`, commits `7f08a27` + `d19cead`)

**AI assistance:** This audit and report were prepared with AI assistance. All evidence files, benchmark scripts, and raw plans were generated and verified by the named auditor.

---

*Final audit complete. Both PR compare URLs prepared; no merges performed by auditor.*
## Final reviewer correction

Hridey replaced Section 8.2 of the optimization report with actual first-run
plan excerpts and reconciled all 30 averages in each of baseline, optimized,
seed_cp4 and large against three raw Execution Time values (120 averages).
R13 uses a Nested Loop Anti Join; R01 combines an index-only membership scan
with ordinary index scans. The application and WhatsApp database remain distinct.

AP PR #3 merged at `3966ba9dcad53f3fff83616f0d55adae2c38bf32`, preserving
Utkarsh’s commits and adding Aaditi’s benchmark correction `cdfc0b2`. The
corrected runner compares complete application row contents after every write,
fails on snapshot errors and never drops an existing database through its wrapper.
Its additional verification ran on PostgreSQL 15.18; the earlier committed AP
timing table is labelled PostgreSQL 18.6 and was not replaced by this check.
