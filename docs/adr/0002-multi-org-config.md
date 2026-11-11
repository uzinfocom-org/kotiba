# One bot user per org in a single Kotiba instance

* Status: proposed
* Deciders: @lambdajon
* Date: 2026-11-09

Technical story: Kotiba already watches repositories from several orgs
(`xinux/*`, `uzinfocom/*` in `default/seed.json`), but it acts through one
Forgejo user: one token, one git identity, one webhook secret
(`src/Config.hs`, `nix/module.nix`). Every comment, review request and
backport PR in every org comes from that same account, and the account needs
access to all orgs.

## Context and Problem Statement

We deploy one Kotiba instance, but each org should have **its own bot user**
in Forgejo. For example, with two orgs `foo` and `bar` we create:

| Org   | Forgejo bot user | Member of | Token |
|-------|------------------|-----------|-------|
| `foo` | `mikki`| `foo` | `mikki` token |
| `bar` | `kotiba-bar` | `bar` |`kotiba-bar` token |

For a repo in `foo`, Kotiba must act as `mikki`: API calls, `git push`
and commit author. For a repo in `bar`, it must act as `kotiba-bar`. No bot
has access outside its own org.

How should Kotiba be configured, and how should it pick the right bot for
each event?

## Decision Drivers

- **Separate bot user per org.** Each org's actions show its own bot as the author.
- Least privilege: a bot's token works only in its own org, so a leaked
  token exposes one org, not all of them.
- One deployment, one database, one process.
- Secrets stay in files an never enter the Nix store.
- Webhook URLs already configured in Forgejo should not have to change.
- A webhook for org A must never be accepted with org B's secret.
- Minimal changes to existing handlers and to the DB schema.

## Considered Options

- **Option 0 — Do nothing.** One shared bot user with access to every org.
- **Option 1 — `[orgs.<name>]` with a bot per org, org resolved from the payload.**
  Kotiba reads `repository.owner.login` from the raw body, verifies the
  signature with that org's secret, and acts as that org's bot.
- **Option 2 — Same config, org resolved from the URL path** (`/webhook/<org>`).
- **Option 3 — One Kotiba instance per org,** each with its own bot.

## Decision Outcome

Chosen option: **Option 1**. Each org gets its own bot user, token and
secret, all inside a single process, and existing webhook URLs keep working.
A forged owner fails verification because the HMAC is checked with the
claimed org's own secret.

Config shape:

```toml
forgejoUrl = "https://git.oss.uzinfocom.uz"   # global, single Forgejo instance

[orgs.foo]
webhookSecret = "/run/secrets/kotiba-foo-webhook"
[orgs.foo.bot]                    # the Forgejo user Kotiba acts as in `foo`
login = "mikki"
frId  = 42
token = "/run/secrets/kotiba-foo-token"
name  = "Mikki"            # git commit author
email = "mikki@ngit.oss.uzinfocom.uz"

[orgs.bar]
webhookSecret = "/run/secrets/kotiba-bar-webhook"
[orgs.bar.bot]
login = "kotiba-bar"
frId  = 32
token = "/run/secrets/kotiba-bar-token"
name  = "Kotiba (bar)"
email = "kotiba-bar@git.oss.uzinfocom.uz"
```

Each org's `bot` is upserted into `users` with the `bot` role at startup.
This replaces the old global `bots` list.

Request flow: read the body, take `repository.owner.login`, look up the org
(unknown -> 403), verify `X-Forgejo-Signature` with that org's secret
(wrong -> 401), decode the payload, and run the handler with `?org` in scope.
All Forgejo API calls and git operations in that handler use `?org.bot`.
Tracking jobs carry the org name, so the worker acts as the same bot.

### Bot setup per org (in Forgejo)

1. Create a bot user (any login, e.g. `mikki`; no `kotiba-` prefix needed) and note its user id (`frId`).
2. Add it to org `<org>` in a team with write access to the tracked repos.
   Write access is needed to push backport branches, open PRs, comment and
   request reviews.
3. Log in as the bot and create an access token with `write:repository`,
   `write:issue` and `read:organization`. Store it as `/run/secrets/kotiba-<org>-token`.
4. In each repo (or at org level), set the webhook to Kotiba's URL, signed
   with `/run/secrets/kotiba-<org>-webhook`.

### Positive Consequences

- Each org sees its own bot as the author of comments, reviews and backport PRs.
- A bot's token works only in its own org, so leaking or revoking it affects one org.
- Each org's credentials can be rotated on their own.
- No DB schema change: `FrId`s are unique within the single Forgejo instance.
- No change to webhook URLs in Forgejo.

### Negative Consequences

- Breaking config change. The top-level `forgejoToken`, `webhookSecret`,
  `identityName`, `identityEmail` and `bots` are replaced by `orgs.<name>`.
  The NixOS module removes the old options with a pointer to the new ones.
- One more Forgejo user and token to create and rotate for each new org.
- A repo in an org that isn't configured is ignored (403), even if the
  webhook is set up.
- The body is parsed twice: once for the owner, once for the full payload.
- Every webhook payload type must carry `repository.owner`. This needs
  checking against the forgejo library.
- Only one Forgejo instance is supported. A per-org `forgejoUrl` would need
  a new ADR and DB changes.

## Pros and Cons of the Options

### Option 0 — Do nothing

- Good, because it needs no work.
- Bad, because one bot needs write access to every org.
- Bad, because one leaked token exposes every org.
- Bad, because every org sees the same bot author.

### Option 1 — Bot per org, org resolved from payload

- Good, because each org gets its own bot with least privilege.
- Good, because webhook URLs stay the same.
- Good, because each org's signature is checked with its own secret.
- Bad, because the owner is read from the body before the body is trusted.
  That's safe because of the per-org HMAC, but it is subtler than routing by path.

### Option 2 — Bot per org, org resolved from URL path

- Good, because the org is known before the body is read, which is simpler to reason about.
- Bad, because every existing Forgejo webhook URL has to be updated.
- Bad, because a misconfigured URL makes one org's events run as another org's bot.

### Option 3 — One instance per org

- Good, because isolation is complete and there are no code changes.
- Bad, because it multiplies services, ports, databases and proxy config.
- Bad, because cross-org reporting (see ADR 0001) needs data from several databases.

## Links

- [ADR 0001 — Track pull requests via Forgejo webhooks](./0001-track-pull-requests-via-webhook.md)
