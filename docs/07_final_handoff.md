# Final checkpoint ownership

The official large-data release announced by Satyaki Das is the CP4 input.
CSV files stay local. Evidence must be committed to the default branches.

| Member | Final responsibility |
|---|---|
| Aaditi | Partitioning DDL, pruning evidence and 100x architecture |
| Shambhavi | Official large-data load, three-run timings and scalability report |
| Utkarsh | AP three-run plans and timings, target review and final cross-repo audit |
| Hridey | This small ownership and submission handoff |

Utkarsh should check all 30 DE targets, explain any misses using plans, verify
the large-data pagination cursor, then finish the 33-query AP timing catalogue.
Use rollback for every timed write. Keep averages traceable to three raw plans.
Do not mark AP CP4 complete until `dbms/05_query_timings.md` and every query's
plans exist on AP main. Each member should review and understand their assigned
AI-assisted changes before the individual analysis.

---

## Completed items (Utkarsh)

- [x] DE: All 30 DE targets checked; all pass on large data (17.5M rows)
- [x] DE: Large-data pagination cursor verified (seed: 20001, large: 2300001)
- [x] DE: 30-query baseline vs optimized table with 5 plan excerpts added to `docs/04_optimization_report.md`
- [x] DE: R13 correctness repair explanation preserved in report
- [x] DE: Large-data 30-query summary averages reconciled to raw plans
- [x] DE: Final validation document created at `docs/08_final_validation.md`
- [x] AP: 33-query catalogue committed (`dbms/04_queries.sql`)
- [x] AP: Benchmark infrastructure committed (`dbms/fixture_data.sql`, `dbms/run_benchmark.py`)
- [x] AP: Timing report template committed (`dbms/05_query_timings.md`)
- [x] AP: Two commits on branch `utkarsh-cp4-benchmark`:
  - `Measure AP queries with repeatable three-run evidence`
  - `Publish AP query timings and scan analysis`
- [x] AP compare URL: https://github.com/hrideymarwah15/SC-Disruption_AP_2026/compare/main...utkarsh-cp4-benchmark (PR to be created)
- [x] DE compare URL: https://github.com/hrideymarwah15/DE_Project_2026/compare/main...utkarsh-cp4-final-audit (PR to be created)
- [x] Both branches pushed; neither PR created yet; neither merged; AP CP4 not marked complete on main

**Note:** AP CP4 not marked complete on main — `dbms/05_query_timings.md` and raw plans exist on AP PR branch only; will be on main after AP PR merge.
