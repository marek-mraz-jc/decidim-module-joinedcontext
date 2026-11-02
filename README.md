# decidim-joinedcontext

A Decidim 0.32 module. An admin of a participatory process or assembly turns on **Publish to context space**, and the space's outputs go straight into a joinedcontext context space, where the platform shares them through MCP and as datasets.

The platform's harvester (`seeds/decidim` in the deployment repository) pulls public Decidim instances. This module is the push path for the platform's own Decidim: same types, same ids, same attributes, within a minute of the change.

## What it sends

| Tick in the setting | Entities |
|---|---|
| (always) | the space as `ParticipatoryProcess` |
| Results | `Result`: progress, status, dates, parent |
| Proposals | `Proposal`: published state and answer, votes unless hidden |
| Budgets | `BudgetProject`: amount, selection, vote total only while the budget shows it |
| Meetings | `Meeting`: dates, place, closed flag, closing report and attendance once visible |

Only what an anonymous visitor reads on the site leaves it. A record that is hidden, withdrawn from view, deleted or unpublished is deleted from the context space on the next commit. A record that stops being sent in any other way (a component unpublished, the option turned off) leaves when its `expiresAt` lease runs out, three days after the last sync.

No author, user, comment, e-mail or phone field is read. Free text loses HTML, e-mail addresses and phone numbers and stops at 2000 characters (`app/services/decidim/joinedcontext/text.rb`).

`proposalAnswer`, `stateLabel`, `closingReport` and `attendeesCount` exist only on this path, because the public GraphQL API hides or lacks them. The target's data model must declare them.

## How it sends

Every commit of a Result, Proposal, Project, Meeting, space or moderation queues a job (Decidim emits no notification for these saves, so the hook is `after_commit` on the models). `decidim_joinedcontext:sync_all` queues a full pass of every active publication; run it nightly. A change of a component's settings also queues a full pass.

Writes are `POST {Endpoint}/ngsi-ld/v1/entityOperations/upsert?options=update` and `.../entityOperations/delete`, 100 entities a batch, 1 MiB a body, with a Keycloak client-credentials token. Connection 5 s, read and write 30 s, answers capped at 256 KiB, no redirects followed. A 429, a 5xx or a network failure retries five times; any other refusal stops and shows in the status line.

## Installation

```ruby
gem "decidim-joinedcontext", git: "https://github.com/marek-mraz-jc/decidim-module-joinedcontext", ref: "<commit>"
```

The gem adds its migration path to the application, so `bin/rails db:migrate` is the only step. Run Sidekiq (or any ActiveJob adapter).

| Environment variable | Meaning |
|---|---|
| `JOINEDCONTEXT_ENDPOINTS` | JSON list of the Endpoints an admin may pick, see below |
| `JOINEDCONTEXT_GATEWAY_HOST` | the one host writes go to; a row on any other host, or without https, is dropped |
| `JOINEDCONTEXT_TOKEN_URL` | the realm's token URL |
| `JOINEDCONTEXT_CLIENT_ID` | the ServiceAccount's client id |
| `JOINEDCONTEXT_CLIENT_SECRET` | its secret, from a Kubernetes Secret; never in Decidim's database or logs |

```json
[{
  "name": "participacia",
  "title": "Participation",
  "url": "https://api.example.org/api/endpoint/<slug>",
  "space": "participacia",
  "instance": "mesto",
  "scope": "/SK/BB/banska_bystrica",
  "locality": "Banská Bystrica",
  "provider": "Mesto Banská Bystrica"
}]
```

`space` and `instance` form the entity ids (`urn:ngsi-ld:Result:{space}:{instance}-{id}`), so they must match the harvester's row when both cover one Decidim. `title` is what the admin sees. An admin only picks a row: no address comes from a form.

The ServiceAccount's Policy grants `upsertBatch`, `createBatch`, `deleteBatch` and `queryBatch` on the types above, on its own space alone.

## The setting

Admin panel, inside the process or assembly: **Publish to context space**. Open to that space's admins and the organization's admins; moderators, collaborators and admins of other spaces are refused. A private space cannot be published.

## Tests

```sh
bundle exec rake test_app
(cd spec/decidim_dummy_app && bundle exec rails db:create db:migrate)
bundle exec rspec
bundle exec rubocop
bundle exec bundle-audit check --update
```

`spec/fixtures/harvester/expected.json` is the harvester's own mapping run in Bento over `input.json`; `generate.py` beside it rewrites it after that mapping changes.

## License

AGPL-3.0-or-later, as Decidim itself.
