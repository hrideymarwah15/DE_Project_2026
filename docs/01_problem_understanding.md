# Problem understanding — SC-Disruption (T0124)

Goal: serve interactive WhatsApp screens quickly while retaining correct
history for operational and analytical workloads.

| Problem | Business need and affected stakeholder | Classification |
|---|---|---|
| P1 | Latest chats and unread badges. **End user/mobile app:** R01, R03. | Real-time |
| P2 | Busy-group history, members and message send. **End user:** R02, R07, W01. | Real-time |
| P3 | Search, message info and reply chains. **End user:** R04, R16, R25. | Search + real-time |
| P4 | Phone lookup, last seen and block check. **Identity/privacy:** R05, R06, R15. | Real-time |
| P5 | Pending-receipt scan, read updates and broadcast receipts. **Delivery service:** R08, W02, W04. | Operational |
| P6 | Accurate unanswered-question list. **Group admin:** R13. | Reporting |
| P7 | Forwarding abuse, evidence console and content deletion. **Trust & safety:** R12, R22, W03. | Reporting + moderation |
| P8 | Heavy uploaders and duplicate files. **Storage team:** R09, R24. | Analytics |
| P9 | Activity, read delay, group health and 20× capacity. **Product/growth:** R10, R14, R17, R19–R21. | Analytics |
| P10 | Stale devices/accounts, missed calls and leaving groups. **Security/platform:** R11, R18, R23, W05. | Operational + reporting |

## Assumptions

- Empty CSV fields mean SQL NULL. Missing receipt times mean the event has not happened.
- Direct chats have two membership rows; group membership can end.
- Read requires delivery first. Deleted rows remain for history while content may be cleared.
- CP1 constraints must accept the unedited seed export.
- CP2 keeps the supplied queries unchanged; measurements determine optimization.
