# Contributing to Kaguya

Thanks for your interest in Kaguya. This document covers local setup and the
expectations for a pull request.

## Local setup

You'll need Elixir/Erlang (see `.tool-versions` or `mix.exs` for versions),
PostgreSQL, and optionally Meilisearch for search.

```sh
git clone <your-fork>
cd kaguya
cp .env.example .env        # fill in DATABASE_URL, SECRET_KEY_BASE, etc.
mix setup                   # deps, DB, assets, git hooks
mix phx.server
```

`mix setup` installs git hooks that enforce formatting on commit/push. See the
[README](README.md) for the full command reference and architecture map.

## Before you open a PR

Run the same checks CI does:

```sh
mix format --check-formatted
mix credo
mix test
```

- **Format** every change (`mix format`). The pre-commit hook enforces this.
- **Match the surrounding code.** Follow the naming, structure, and comment
  density already present in the files you touch.
- **Keep PRs focused.** One logical change per PR is easier to review than a
  mixed bag.
- **Add or update tests** for behavior changes. Some integration tests need a
  VNDB dump DB or external services; unit tests should run against the
  fake/safe defaults in `config/test.exs`.

## Commit messages

Use clear, conventional-style prefixes where they fit (`feat:`, `fix:`,
`refactor:`, `docs:`, `chore:`) and write the body to explain *why*, not just
*what*.

## Finding something to work on

Kaguya is maintained part-time, so a little coordination up front saves
everyone wasted effort.

- **Bugs:** check the [Issues](../../issues) tab. Anything not already assigned
  is fair game. Comment to claim it, then open a PR referencing the issue.
- **Features and larger changes:** please open or join a thread in
  [Discussions](../../discussions) before writing code. Building a big feature
  no one has agreed to is the most common way a PR stalls. A quick conversation
  first means your time goes toward something that'll actually get merged.
- **Small, obvious fixes** (typos, docs, a clear bug with an obvious fix) don't
  need a discussion. Just send the PR.

PRs without an associated issue or discussion may still be merged, but reviews
prioritize changes that have been talked through.

## License

By contributing, you agree that your contributions are licensed under the
project's [AGPL-3.0](LICENSE).
