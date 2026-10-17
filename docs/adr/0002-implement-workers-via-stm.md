# Implement durable workers for webhook jobs

* Status: proposed
* Deciders: @lambdajon @xfeusw
* Date: 2026-10-15

Technical story: We need to make our app work more effective, so it would be wise if our app uses concurrency.
No handler of webhook should work inline, Kotiba needs a separate system for jobs. See the existing implementation:
[Events.Tracking.Worker](https://git.oss.uzinfocom.uz/uzinfocom/kotiba/src/commit/1f33d1ea8b86e45929d385f4a3da6101cf1194e8/src/Events/Tracking/Worker.hs)

## Context and Problem Statement

Right now every handler of webhook works inline, in the request of Forgejo. Backport (clone, cherry-pick, push)
is slow, but Forgejo waits only short time for the answer, so a slow handler makes the delivery look failed while
the work still goes on. Only PR tracking has its own worker: one thread with in-memory queue. If Kotiba restarts,
queued jobs are lost and nobody knows about it.

How should Kotiba run the work of webhooks, so that the answer is fast, slow jobs don't block fast ones,
and jobs survive restarts and failures?

## Decision Drivers

- Webhook must answer fast, no work inline.
- Slow jobs (e.g. git) must not block fast ones, and no worker is tied to one kind of job.
- Jobs must survive restart and must be retriable.
- Load on the Forgejo server and our database should stay bounded.
- Jobs of the same thing must not overlap (shared clone of repository, rows of the same PR).
- Every job should be traceable by delivery id and visible (status, attempts, failure).
- Should reuse existing infrastructure, Postgres is already there.

## Considered Options

- **Option 0 — Keep inline handlers.** Only tracking has its worker, as it is now.
- **Option 1 — In-memory queue (STM) with generic workers.** No persistence.
- **Option 2 — Durable jobs in Postgres with generic workers.** Table `jobs` is the queue, STM only wakes workers.
- **Option 3 — External queue.** Redis, RabbitMQ or similar.

## Decision Outcome

Chosen option: **Option 2 — Durable jobs in Postgres with generic workers**, because jobs must survive restarts and
we already have Postgres, so there is nothing new to run. STM stays in the design, but only as the way to wake workers
and to count what is running.

How it works:

- **Handler.** It parses the delivery, inserts jobs in one transaction, wakes workers and answers 200.
  If the insert fails it answers 500, so Forgejo shows the delivery as failed and it can be redelivered.
  Jobs are unique by kind and delivery id, so a redelivery doesn't enqueue twice. A redelivery of a failed job puts it back to pending.
- **Workers.** A pool of generic workers, any worker can run any kind of job. A worker claims the oldest pending job whose
  time has come and whose key has no running job (`FOR UPDATE SKIP LOCKED`). Workers sleep until a signal or until
  the next job is due.
- **Keys.** Key says what must not run twice at once, for example `pr:<repo>:<number>` for tracking or `repo:<id>` for
  the shared clone. At most one running job per key, oldest first among the ready ones. A job which waits for retry
  doesn't block newer jobs with the same key.
- **Restart.** Attempts are counted when a job is claimed, not when it fails, so a job which kills the process is
  given up after some tries. At start, jobs which are still `running` go back to `pending`.
- **Retries.** Temporary errors (network, Forgejo 5xx, timeout) are retried with backoff, the waiting time grows
  after each attempt (for example 10 seconds, 1 minute, 10 minutes, 1 hour) and after 5 attempts the job is failed.
  Permanent errors (conflict, missing role, payload which can't be decoded) fail at once. Each job error type says
  which of them are temporary.
- **Timeouts.** Every job runs under a timeout, so a hung git process can't hold a worker forever.
- **Payload.** Job keeps the raw body of delivery (not the one which we encode again), so it can run again after restart.
  The payload is cleared when the job succeeds, because it has personal data (e.g. emails). Failed jobs keep it
  for 30 days. Old rows are removed by a maintenance step.
- **Outcome.** A job doesn't touch the queue, it returns what should happen, and the worker applies it in one transaction:
  `Done`, `Continue [jobs]` (these follow), `Retry delay reason`, or `Failed reason [jobs]` (finalizers, e.g. a comment).
- **Backport.** One job per source PR and target branch, created by the handler. It has sub-jobs for its steps:
  - `Pick`: key `repo:<id>`, fetch or clone, checkout, cherry-pick. A conflict is a permanent failure.
  - `Push`: key by branch, `push -f` of the backport branch.
  - `OpenPr`: key by PR, creates the PR. On 409 it looks up the existing PR by base and head and records it as opened.
  - `Notify`: comment about the failure, created only on permanent failure. It looks for a hidden marker in existing comments first.
- **Supervision.** Workers run with `async`, they live and die with the server and a crashed worker is not unnoticed.
  The process exits, systemd restarts it, and orphaned jobs are reclaimed at start.
- **Overload.** The queue is not bounded, we don't answer 503. Number of pending jobs is shown in `/health`.

### Positive Consequences

- Webhook answers fast, slow git work doesn't delay anything.
- Jobs survive restarts and are retried by themselves after temporary failures.
- Every job is visible: status, attempts, failure, and which step of backport has failed.
- Number of workers limits parallel calls to Forgejo and git.
- A step of backport is retried alone, an outage of Forgejo at PR creation doesn't repeat clone and cherry-pick.
- PR tracking becomes one kind of job, it doesn't need its own worker and queue.

### Negative Consequences

- Jobs run at least once, so every job must be safe to run twice. Tracking already is.
  Reviewer assignment must choose the reviewer without randomness (from hash of repository and PR number) and skip closed PRs.
  Backport needs the 409 lookup and comments only at the final failure.
- More code and schema: columns for key, attempts, time of next run, parent and output of step, handling of `Outcome`.
- Postgres is used as queue: rows are updated often, so old ones must be removed.
  Reclaiming of `running` jobs at start is correct only for a single instance of Kotiba, more instances need leases.
- Answer 200 depends on database. If it is down the answer is 500, and Forgejo can redeliver later.
- Stored payload may stop decoding after upgrade of the forgejo library. Such job fails with the reason and can be put back after the fix.
- Number of workers must stay under the size of connection pool, and a job must not hold a connection while it calls Forgejo or git.
- Helpers of git need fixes before backport runs in workers: `fetch` must use the auth header,
  clone must go to temporary directory and be renamed, `withGit` needs a timeout.

## Pros and Cons of the Options

### Option 0 — Keep inline handlers

- Good, because there is nothing to implement.
- Bad, because slow handlers make Forgejo mark the delivery as failed and keep the request thread busy.
- Bad, because one slow handler delays the rest of handlers of the same event.
- Bad, because queued tracking jobs are lost on restart.

### Option 1 — In-memory queue (STM) with generic workers

- Good, because it is simple, with no new schema.
- Good, because workers decouple the answer from the work.
- Bad, because jobs are lost on restart, and a lost backport gives no comment and no record.
- Bad, because there is no visibility and no retry after restart.

### Option 2 — Durable jobs in Postgres with generic workers

- Good, because jobs survive restarts, can be retried and can be seen in the table.
- Good, because Postgres is already part of Kotiba.
- Good, because the queue and the data of tracking share the database and one backup.
- Bad, because the queue load goes to the database, and old rows need cleaning.
- Bad, because every job must be safe to run twice.

### Option 3 — External queue

- Good, because durable queues with retry and delay are what these systems do.
- Bad, because it is one more service to run, update and monitor for a small amount of jobs.
- Bad, because a job and its database changes can't be saved in one transaction.

### Ideas which we looked at and did not take

- **Sub-jobs as separate rows only in the chain, or one job with a `step` column.** The `step` column resumes in the same way with less machinery,
  but sub-jobs allow different keys, timeouts and visibility per step, which backport needs.
- **Saga.** Pushed branch which is left behind is harmless, so steps need no compensation.
- **Event sourcing.** It rebuilds state, but our problem is repeating side effects. Tracking already keeps events.
- **Durable execution engines (Temporal style).** They need deterministic replay and versioning, too heavy for three kinds of jobs.

## Links

- Existing implementation:
  [Events.Tracking.Worker](https://git.oss.uzinfocom.uz/uzinfocom/kotiba/src/commit/1f33d1ea8b86e45929d385f4a3da6101cf1194e8/src/Events/Tracking/Worker.hs)
