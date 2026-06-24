defmodule Mix.Tasks.Kaguya.DeleteUser do
  @moduledoc """
  Delete a user and clean up all denormalized counters.

  ## Usage

      # Dry run (default) — shows what would be affected
      mix kaguya.delete_user --username foo
      mix kaguya.delete_user --id <uuid>

      # Actually execute
      mix kaguya.delete_user --username foo --execute

      # Run locally against a remote DB (IPv4 session pooler)
      mix kaguya.delete_user --username foo --database-url "postgresql://USER:PASSWORD@HOST:5432/postgres"

      # Run locally against a remote DB (IPv6 direct connection)
      mix kaguya.delete_user --username foo --ipv6 --database-url "postgresql://USER:PASSWORD@HOST:5432/postgres"
  """

  use Mix.Task

  import Ecto.Query

  alias Kaguya.Repo
  alias Kaguya.Users
  alias Kaguya.Users.User
  alias Kaguya.Reviews.{Rating, Review, ReviewComment}
  alias Kaguya.Similarities.SimilarityVote
  alias Kaguya.Lists.{List, ListComment}
  alias Kaguya.Social.Notification

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          username: :string,
          id: :string,
          execute: :boolean,
          database_url: :string,
          ipv6: :boolean
        ]
      )

    if db_url = Keyword.get(opts, :database_url) do
      inet = if Keyword.get(opts, :ipv6, false), do: :inet6, else: :inet

      Application.put_env(:kaguya, Kaguya.Repo,
        url: db_url,
        socket_options: [inet],
        pool_size: 5,
        timeout: :infinity,
        parameters: [statement_timeout: "0"]
      )
    end

    Mix.Task.run("app.start")

    execute? = Keyword.get(opts, :execute, false)

    user = resolve_user!(opts)
    print_summary(user)

    if execute? do
      delete!(user)
      Mix.shell().info("\nDone.")
    else
      Mix.shell().info("\nDry run. Pass --execute to delete.")
    end
  end

  defp resolve_user!(opts) do
    result =
      cond do
        username = Keyword.get(opts, :username) -> Repo.get_by(User, username: username)
        id = Keyword.get(opts, :id) -> Repo.get(User, id)
        true -> Mix.raise("Must provide --username or --id")
      end

    result || Mix.raise("User not found")
  end

  defp print_summary(user) do
    uid = user.id

    # User's own data (CASCADE-deleted)
    ratings_count = count(Rating, uid)
    reviews_count = count(Review, uid)
    lists_count = count(List, uid)
    review_comments = count(ReviewComment, uid)
    list_comments = count(ListComment, uid)
    sim_votes = count(SimilarityVote, uid)

    # Denormalized impact on others' content
    reviews_affected =
      Repo.one(
        from(rc in ReviewComment,
          where: rc.user_id == ^uid,
          select: count(rc.vn_review_id, :distinct)
        )
      )

    lists_affected =
      Repo.one(
        from(lc in ListComment,
          where: lc.user_id == ^uid,
          select: count(lc.list_id, :distinct)
        )
      )

    vns_affected =
      Repo.one(
        from(r in Rating,
          where: r.user_id == ^uid,
          select: count(r.visual_novel_id, :distinct)
        )
      )

    IO.puts("\n#{String.duplicate("=", 60)}")
    IO.puts("  User: #{user.username} (#{user.id})")
    IO.puts(String.duplicate("=", 60))

    IO.puts("\n  CASCADE deletes (user's own data):")
    IO.puts("    VN ratings:           #{ratings_count}")
    IO.puts("    VN reviews:           #{reviews_count}")
    IO.puts("    VN lists:             #{lists_count}")
    IO.puts("    Review comments:      #{review_comments}")
    IO.puts("    List comments:        #{list_comments}")
    IO.puts("    Similarity votes:     #{sim_votes}")

    IO.puts("\n  Counter adjustments (on others' content):")
    IO.puts("    Reviews comments_count: #{reviews_affected} reviews")
    IO.puts("    Lists comments_count:   #{lists_affected} lists")
    IO.puts("    Similarity vote counts: #{sim_votes} pairs")
    IO.puts("    VN rating stats:        #{vns_affected} VNs")
    IO.puts("    VN reviews_count:       #{reviews_count} VNs")

    uid_str = Ecto.UUID.cast!(uid)

    actor_notifications =
      Repo.one(
        from(n in Notification,
          where:
            n.user_id != ^uid and
              fragment(
                "EXISTS (SELECT 1 FROM jsonb_array_elements(?->'actor_snapshots') AS s WHERE s->>'id' = ?)",
                n.metadata,
                ^uid_str
              ),
          select: count()
        )
      )

    IO.puts("\n  Cleanup (stale refs on others):")
    IO.puts("    Notifications (entity): reviews=#{reviews_count} lists=#{lists_count}")
    IO.puts("    Notifications (actor):  #{actor_notifications}")
    IO.puts("    Activities:             reviews=#{reviews_count} lists=#{lists_count}")

    IO.puts(String.duplicate("=", 60))
  end

  defp count(schema, user_id) do
    Repo.one(from s in schema, where: s.user_id == ^user_id, select: count())
  end

  defp delete!(user) do
    Mix.shell().info("Deleting from database...")

    case Users.delete_user(user.id) do
      {:ok, true} -> Mix.shell().info("  Database done.")
      {:error, reason} -> Mix.raise("Database deletion failed: #{inspect(reason)}")
    end
  end
end
