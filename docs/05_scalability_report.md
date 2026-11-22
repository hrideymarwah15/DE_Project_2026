# CP4 scalability results — SC-Disruption T0124

## Measured setup

The official faculty large-data release was loaded into a fresh database using
our CP1 schema and CP3 indexes. It contains 17,543,347 rows, including 2,400,000
messages and 10,022,212 receipts. Archive SHA-256:
`87745026da843423d1af090cc6845b65b8374358b56d5b9eedad27babded8c2e`.
CSV files are excluded from Git. `benchmarks/load_large.sh` repeats the load.

The active server is PostgreSQL 18.6, Asia/Kolkata. CP3 originally used 15.18;
therefore we reran the optimized seed workload on 18.6 (`seed_cp4/`) and compare
that run here. Do not attribute version differences to data growth. Both phases
used three sequential EXPLAIN (ANALYZE, BUFFERS) runs on the same computer.
These are local microbenchmarks, not concurrent-user or cold-cache guarantees.

## All 30 averages

| Query | Seed ms | Large ms | Large / seed | Target ms (under) | Result |
|---|---:|---:|---:|---:|---|
| R01 | 0.176 | 0.549 | 3.12 | 5 | Pass |
| R02 | 0.253 | 0.038 | 0.15 | 5 | Pass |
| R03 | 0.323 | 0.396 | 1.23 | 5 | Pass |
| R04 | 0.449 | 0.259 | 0.58 | 250 | Pass |
| R05 | 0.043 | 0.244 | 5.67 | 5 | Pass |
| R06 | 0.182 | 0.264 | 1.45 | 5 | Pass |
| R07 | 0.293 | 0.369 | 1.26 | 5 | Pass |
| R08 | 13.594 | 17.648 | 1.30 | 250 | Pass |
| R09 | 18.295 | 522.580 | 28.56 | 5000 | Pass |
| R10 | 3.478 | 89.100 | 25.62 | 5000 | Pass |
| R11 | 0.785 | 10.445 | 13.31 | 250 | Pass |
| R12 | 6.085 | 143.345 | 23.56 | 5000 | Pass |
| R13 | 0.192 | 0.153 | 0.80 | 250 | Pass |
| R14 | 5.558 | 79.934 | 14.38 | 5000 | Pass |
| R15 | 0.049 | 0.124 | 2.53 | 5 | Pass |
| R16 | 0.138 | 0.193 | 1.40 | 5 | Pass |
| R17 | 31.424 | 520.344 | 16.56 | 5000 | Pass |
| R18 | 29.505 | 312.832 | 10.60 | 5000 | Pass |
| R19 | 31.199 | 819.582 | 26.27 | 5000 | Pass |
| R20 | 89.144 | 2353.280 | 26.40 | 5000 | Pass |
| R21 | 25.415 | 188.804 | 7.43 | 5000 | Pass |
| R22 | 0.064 | 0.113 | 1.77 | 250 | Pass |
| R23 | 3.683 | 90.650 | 24.61 | 250 | Pass |
| R24 | 12.667 | 496.385 | 39.19 | 5000 | Pass |
| R25 | 0.105 | 0.125 | 1.19 | 5 | Pass |
| W01 | 1.790 | 3.056 | 1.71 | 5 | Pass |
| W02 | 0.591 | 0.761 | 1.29 | 5 | Pass |
| W03 | 1.065 | 1.343 | 1.26 | 5 | Pass |
| W04 | 71.616 | 70.020 | 0.98 | 2000 | Pass |
| W05 | 0.277 | 0.754 | 2.72 | 5 | Pass |


All averages reconcile to three raw Execution Time values. All 30 targets pass
in this run. There were no target failures requiring an additional index.
R09, R10, R12, R19, R20, R23 and R24 grew more than 20 times. Their scans,
aggregation, sorting and cache pressure grow with the working set; the evidence
does not isolate one cause. R20 is closest to the analytics limit at 2353 ms.
R14 and R17 grow approximately with data volume; indexed point lookups remain
sub-millisecond or close to it. Some queries get faster because fixed identifiers
select different local distributions and cache state differs. This is not proof
that larger data is intrinsically faster.

## Pagination and write safety

For R22 we derived the cursor before timing using offset 99999 in the large
dataset: 2300001. The timed query uses message_id < 2300001, with no OFFSET.
The seed cursor 20001 is not reused. `queries/workload_30_large.sql` records the
large workload; all other SQL is the same as the optimized seed workload.
Each WRITE executes in BEGIN / ROLLBACK. `verify_write_state.sql` captures counts
and all rows targeted by W01-W05; before and after outputs were identical.

## Storage and architecture

| Dataset | Database bytes | Table bytes | Index bytes |
|---|---:|---:|---:|
| Seed | 132019903 | 64430080 | 58810368 |
| Large | 2387924671 | 1260412928 | 1118937088 |

Database totals also include catalog and other overhead. These measurements were
taken after index construction; later vacuum or activity can change them.
See `06_architecture.md` for monthly partitioning, chat-based sharding, replicas,
caching and maintenance. `sql/08_partitioning.sql` and the committed pruning plan
show the reversible experiment and explain the partitioned primary-key rule.
At 100x seed, linear storage projection from this large run is about 11.9 GB;
this excludes replicas, backup space, WAL, headroom and workload changes.

The tested dataset meets the stated targets. Readiness for real traffic still
requires concurrent load, replica-lag, failure recovery and backup-restore tests.
AP CP4 timings remain Utkarsh's separate responsibility. These changes were
prepared with AI assistance and should be understood by each assigned reviewer.
