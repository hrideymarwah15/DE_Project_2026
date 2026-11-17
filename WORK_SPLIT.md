# SC-Disruption DBMS work split

This plan covers the remaining checkpoints. Ownership means the named member
must understand, review and commit that work from their own GitHub account.
Another member should review every deliverable before the deadline.

## CP1 — schema and normalization

| Owner | Work | Status |
|---|---|---|
| Hridey | docs/01_problem_understanding.md; coordinate integration and validation; complete the transferred AP normalization task | Prepared and verified |
| Aaditi | docs/02_schema_design.md; diagrams/er_diagram.mmd and .svg | Prepared and verified |
| Shambhavi | sql/01_schema.sql; sql/02_load_data.sql; fresh-database load and integrity checks | Prepared and verified |
| Utkarsh | Original AP normalization assignment transferred to Hridey | Completed by Hridey in the AP repo |

## CP2 — baseline timings

| Owner | Work |
|---|---|
| Hridey | Run and preserve the 30-query baseline; verify write queries roll back |
| Aaditi | Build the AP ER diagram in dbms/02_er_diagram.* |
| Shambhavi | Build and test AP PostgreSQL schema in dbms/03_schema.sql |
| Utkarsh | Independently audit baseline plans and help write scan-type explanations |

Hridey integrates docs/03_baseline_timings.md only after raw plan files and
summary.csv agree. CP2 uses the same laptop/database environment later used
for CP3.

## CP3 — optimization

| Owner | Work |
|---|---|
| Hridey | Design and justify indexes in sql/05_indexes.sql |
| Aaditi | Rewrite selected queries in sql/06_optimized_queries.sql; prove identical results |
| Shambhavi | Run optimized benchmarks; report before/after plans, write overhead and index sizes |
| Utkarsh | List every query used by the AP app in dbms/04_queries.sql |

All four review the NULL-related wrong-result query. The final report must use
measured values from committed raw plans.

## CP4 — final submission

| Owner | Work |
|---|---|
| Hridey | Integrate docs/05_scalability_report.md and verify every target |
| Aaditi | Design/test sql/08_partitioning.sql; document pruning and 100× architecture |
| Shambhavi | Load the faculty large dataset and run optimized large-data benchmarks |
| Utkarsh | Run AP query timings and commit dbms/05_query_timings.md plus dbms/plans/ |

## CP5 — individual analysis

Each member prepares independently to explain the constraints, their own
queries/indexes, the relevant EXPLAIN plans, before/after evidence, tradeoffs
and any remaining scalability risk. CP5 is individual work in class.

## Review rhythm

1. Owner commits a small, focused change from their own account.
2. A different member runs or reads it and records corrections in a follow-up
   commit.
3. Hridey checks the tracker after its scheduled refresh.
4. No invented timings, copied diagrams or borrowed reports are accepted.
