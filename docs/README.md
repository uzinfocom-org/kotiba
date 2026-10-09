# Architecture Decision Records

This directory records significant architecture decisions for Kotiba.

- **RFCs** (`docs/rfc/`) are proposals and designs under discussion. They can be long and change often.
- **ADRs** (`docs/adr/`) record a decision once it is made: short, dated, and never rewritten. To change a decision, write a new ADR that supersedes the old one and update the old one's status line.

## Process

1. Copy [`template.md`](template.md) to `NNNN-short-title.md` using the next free number.
2. Open a PR with status **Proposed**.
3. On merge after agreement, set status to **Accepted** and add it to the index below.

## Index

| ADR | Title | Status | Date |
|---|---|---|---|
| [0001](./adr/0001-track-pull-requests-via-webhook.md) | Tracking pull requests | Accepted | 2026-09-29 |