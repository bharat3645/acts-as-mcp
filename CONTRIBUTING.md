# Contributing to acts-as-mcp

Thanks for looking under the hood. This project values small, verifiable changes.

## Ground rules

- **Every change ships with evidence.** Bug fix → a test that fails without it. Feature → tests that pin its behavior AND its failure modes. This repo documents what it *doesn't* do as carefully as what it does — PRs that quietly widen claims get asked to narrow them.
- **The zero-dependency core is a feature, not an accident.** The server itself implements the Rack env contract directly and has zero runtime dependencies — CI proves this by running the core suite (`test/server_core_test.rb`) with no gems installed at all. ActiveRecord integration (`test/model_test.rb`, the `expose:` API) is opt-in on top of that core; it's real functionality, not a stretch goal, but it must stay optional. If your change adds a runtime dependency to `lib/`, or makes the core suite require a gem to run, open an issue discussing why first.
- **Honest docs.** If your change has a limitation, the README states it. "Documented honestly" beats "silently best-effort".

## Getting started

```sh
bundle exec rake test
```

This runs the full suite (server core + ActiveRecord integration) and is what CI runs in its main job. CI also runs a second, separate job with **no gems installed at all** — `ruby -Ilib -Itest test/server_core_test.rb` — which is how the zero-runtime-dependency claim above is actually enforced rather than just asserted. If you touch anything under `lib/`, it's worth running that bare command locally too:

```sh
ruby -Ilib -Itest test/server_core_test.rb
```

CI runs both of these, plus the examples and benchmark for real (not just as committed static text); green CI is required, no exceptions (including for maintainers — check the history: it's how the whole repo was built).

## Good first issues

Issues tagged `good-first-issue` are scoped to be completable without deep context; each states the acceptance evidence expected. If you want one and it's unclear, comment — you'll get a response, not silence.

## Reporting security issues

Email 404ghost.2@gmail.com rather than opening a public issue. You'll get an acknowledgment within 48h and honest handling: if it's real, it ships as a fix with credit; if it's out of threat model, the threat-model doc gets clearer about why.
