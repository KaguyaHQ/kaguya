defmodule Kaguya.Release do
  @moduledoc """
  Provides functions to run database migrations in production when Mix is not available,
  such as in compiled releases.

  ## Overview

  In production we deploy a compiled release that doesn't include Mix, so
  `mix ecto.migrate` isn't available. Instead, this module leverages
  `Ecto.Migrator` to safely execute migrations.

  It ensures that:
    - Only pending migrations (tracked via the `schema_migrations` table) are applied.
    - Database tasks are executed in a controlled manner without Mix.
    - Migrations can be automated (via a release command in your deployment config)
      or run manually via SSH.

  ## Usage

  To run migrations in your production release, invoke:

      /app/bin/kaguya eval "Kaguya.Release.migrate"

  In our deploy, this is called from `/home/deploy/kaguya/deploy.sh` before
  `docker compose up -d`, so each deploy applies pending migrations.

  ## Best Practices

  - **Automatic Migrations:** For small, incremental, and backward-compatible changes,
    using this module via an automated release command is recommended.

  - **Manual Migrations:** For risky or large schema changes, consider deploying first,
    then manually running the migration command (e.g., via SSH) to maintain full control.

  - Always ensure that migrations are designed to be backward-compatible to avoid
    downtime during rolling deploys.

  This module is the recommended approach for handling production database migrations
  in environments where Mix is unavailable.
  """
  @app :kaguya

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Manually marks a migration as applied without running it.
  Useful when a migration partially applied (tables exist) but timed out
  before being recorded in schema_migrations.

  Example: mark_as_migrated(Kaguya.Repo, 20250928121502)
  """
  def mark_as_migrated(repo, version) when is_integer(version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        # Insert the version into schema_migrations
        repo.insert_all(
          "schema_migrations",
          [
            %{
              version: version,
              inserted_at: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
            }
          ],
          on_conflict: :nothing
        )

        IO.puts("Marked migration #{version} as applied")
        :ok
      end)
  end

  @doc """
  Lists all applied migrations in the database.

  Example: list_migrations(Kaguya.Repo)
  """
  def list_migrations(repo) do
    load_app()

    {:ok, result, _} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        import Ecto.Query

        versions =
          repo.all(
            from m in "schema_migrations",
              select: m.version,
              order_by: [desc: m.version]
          )

        IO.puts("\nApplied migrations:")
        Enum.each(versions, fn v -> IO.puts("  #{v}") end)
        IO.puts("")

        versions
      end)

    result
  end

  @doc """
  Removes a migration from schema_migrations without rolling it back.
  Useful when you need to re-run a partially applied migration.

  Example: unmark_migration(Kaguya.Repo, 20250928121502)
  """
  def unmark_migration(repo, version) when is_integer(version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, fn _repo ->
        import Ecto.Query

        repo.delete_all(from m in "schema_migrations", where: m.version == ^version)
        IO.puts("Removed migration #{version} from schema_migrations")
        :ok
      end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
