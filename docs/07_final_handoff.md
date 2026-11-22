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
