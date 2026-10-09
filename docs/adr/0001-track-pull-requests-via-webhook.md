# Track pull requests via Forgejo webhooks

* Status: accepted
* Deciders: @lambdajon @xfeusw
* Date: 2026-09-29

Technical story: We need reports about our process based on contributions,
so Kotiba must record and track pull requests. See the existing handler:
[onPullRequest](https://git.oss.uzinfocom.uz/uzinfocom/kotiba/src/commit/1b8b19a33cd7aa6466e65d6e9c604bb71e918465/src/API.hs#L28).

## Context and Problem Statement

Tracking is used to prepare reports about our process based on
contributions. We currently have the following open questions:

- How many PRs were made this month?
- Who contributed how much during that period?
- What work was done during the PR activities?

How should Kotiba record and track pull requests across the
repositories it watches?

## Decision Drivers

- Must record all pull requests.
- Must support filtering by date interval, users, and selected repositories.
- Should reuse existing infrastructure where possible — Kotiba already
  has a webhook interface and an `onPullRequest` handler.
- Load on the Forgejo server and our database should stay bounded.
- individual PR events should be traceable end-to-end and retryable.

## Considered Options

- **Option 0 — Do nothing.** Continue without automated PR tracking.
- **Option 1 — Webhook.** Extend the existing webhook interface and
  `onPullRequest` handler to record and track every PR change as it happens.
- **Option 2 — Fetch and synchronize in background.** Run a background job that periodically fetches all pull requests from the tracked repositories and synchronizes local state.

## Decision Outcome

Chosen option: **Option 1 — Webhook**, because we already have the capability to handle pull requests and their associated events. Extending this interface is relatively low-cost and gives us real-time tracking with per-event traceability.

### Positive Consequences

- Since we already have PR events in place, implementing this functionality will be quick.
- Every event carries an identifier (`X-Forgejo-Delivery`), making it easy to trace a PR end-to-end through the system and to retry ndividual sub-processes of a specific flow.

### Negative Consequences

- We will need to isolate handlers so that a failure in one does not
  block subsequent handlers for the same event.
- We will need to measure and cap per-event handler latency, since
  handlers for a single event now run sequentially.
- Handler complexity for the shared `onPullRequest` event will grow;
  we should keep an eye on it and split responsibilities if it becomes
  hard to reason about.

## Pros and Cons of the Options

### Option 0 — Do nothing

Skip automated tracking entirely.

- Bad, because it does not answer the reporting questions that motivate
  this ADR — manual counting does not scale past a handful of
  repositories.

### Option 1 — Webhook

Track all PR events via the existing webhook interface.

- Good, because we have an existing interface and event types.
- Good, because events can be processed concurrently across the fleet.
- Good, because it is easy to trace an end-to-end flow via event identifiers.
- Bad, because handlers for the same event can interfere with each other — an exception in one handler must not prevent the rest from running.
- Bad, because handlers for a single event run sequentially, so one low handler adds latency to the rest.

### Option 2 — Fetch and synchronize in background

Periodically fetch all pull requests from the tracked repositories.

- Good, because the process runs asynchronously and independently of live PR traffic.
- Good, because it is easy to manage deactivation, reuse, and synchronization schedules when needed.
- Bad, because it can generate a large number of requests, putting excessive load on our database and the Forgejo server.
- Bad, because monitoring the status of background jobs in real time is relatively difficult, and tracing is harder because we fetch all PRs at once.

## Links

- Existing handler:
  [onPullRequest in `src/API.hs`](https://git.oss.uzinfocom.uz/uzinfocom/kotiba/src/commit/1b8b19a33cd7aa6466e65d6e9c604bb71e918465/src/API.hs#L28)
