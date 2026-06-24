defmodule Kaguya.Users.FavoriteQuotesTest do
  @moduledoc """
  Tests for the inline-pin / bulk-replace favorite-quote flows in
  `Kaguya.Users`. Covers limit enforcement, idempotency, prepend
  ordering, the row lock that protects concurrent adds from beating the
  cap, and cascade behavior on quote/user delete.
  """
  use ExUnit.Case, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Kaguya.Characters.{Quote, QuoteFavorite}
  alias Kaguya.Repo
  alias Kaguya.Test.UserFixtures
  alias Kaguya.Users
  alias Kaguya.VisualNovels
  alias Kaguya.VisualNovels.VisualNovel

  setup do
    :ok = Sandbox.checkout(Repo)
    Sandbox.mode(Repo, {:shared, self()})

    user = UserFixtures.insert_user!()
    vn = insert_vn!()
    quotes = for n <- 1..7, do: insert_quote!(vn, "Quote #{n} text body.")

    %{user: user, vn: vn, quotes: quotes}
  end

  describe "add_favorite_quote/2" do
    test "pins a quote and bumps favorites_count", %{user: user, quotes: [q | _]} do
      assert {:ok, true} = Users.add_favorite_quote(user, q.id)

      assert Repo.get_by(QuoteFavorite, user_id: user.id, vn_quote_id: q.id)
      assert Repo.get!(Quote, q.id).favorites_count == 1
    end

    test "is idempotent — re-pinning the same quote does not duplicate or double-count",
         %{user: user, quotes: [q | _]} do
      {:ok, true} = Users.add_favorite_quote(user, q.id)
      {:ok, true} = Users.add_favorite_quote(user, q.id)

      assert Repo.aggregate(
               from(qf in QuoteFavorite, where: qf.user_id == ^user.id),
               :count
             ) == 1

      assert Repo.get!(Quote, q.id).favorites_count == 1
    end

    test "returns :limit_exceeded when the user is already at the cap",
         %{user: user, vn: vn} do
      limit = Kaguya.Users.User.quote_favorites_limit(user)
      quotes = for n <- 1..(limit + 1), do: insert_quote!(vn, "Cap quote #{n} text body.")

      # Pin the full allowance, then attempt one over.
      for q <- Enum.take(quotes, limit), do: {:ok, true} = Users.add_favorite_quote(user, q.id)

      over = Enum.at(quotes, limit)
      assert {:error, :limit_exceeded} = Users.add_favorite_quote(user, over.id)

      # No partial write — counter on the rejected quote should stay 0.
      assert Repo.get!(Quote, over.id).favorites_count == 0
    end

    test "concurrent adds racing the limit can never go over (row lock holds)",
         %{user: user, vn: vn} do
      limit = Kaguya.Users.User.quote_favorites_limit(user)
      quotes = for n <- 1..(limit + 1), do: insert_quote!(vn, "Race quote #{n} text body.")

      # Fill all but one slot, then race two parallel adds for the last slot.
      for q <- Enum.take(quotes, limit - 1),
          do: {:ok, true} = Users.add_favorite_quote(user, q.id)

      [qa, qb] = quotes |> Enum.drop(limit - 1) |> Enum.take(2)

      results =
        [qa, qb]
        |> Task.async_stream(fn q -> Users.add_favorite_quote(user, q.id) end,
          max_concurrency: 2,
          timeout: 5_000
        )
        |> Enum.map(fn {:ok, r} -> r end)

      # Exactly one should succeed; the other must hit :limit_exceeded.
      successes = Enum.count(results, &match?({:ok, true}, &1))
      rejections = Enum.count(results, &match?({:error, :limit_exceeded}, &1))

      assert successes == 1
      assert rejections == 1

      assert Repo.aggregate(
               from(qf in QuoteFavorite, where: qf.user_id == ^user.id),
               :count
             ) == limit
    end

    test "prepend semantics — newer pins land before older ones",
         %{user: user, quotes: [q1, q2, q3 | _]} do
      {:ok, true} = Users.add_favorite_quote(user, q1.id)
      {:ok, true} = Users.add_favorite_quote(user, q2.id)
      {:ok, true} = Users.add_favorite_quote(user, q3.id)

      ordered =
        from(qf in QuoteFavorite,
          where: qf.user_id == ^user.id,
          order_by: [asc: qf.position],
          select: qf.vn_quote_id
        )
        |> Repo.all()

      # q3 was pinned last, must appear first.
      assert ordered == [q3.id, q2.id, q1.id]
    end
  end

  describe "remove_favorite_quote/2" do
    test "removes a pinned quote and decrements favorites_count",
         %{user: user, quotes: [q | _]} do
      {:ok, true} = Users.add_favorite_quote(user, q.id)
      {:ok, true} = Users.remove_favorite_quote(user, q.id)

      refute Repo.get_by(QuoteFavorite, user_id: user.id, vn_quote_id: q.id)
      assert Repo.get!(Quote, q.id).favorites_count == 0
    end

    test "is idempotent — removing a quote that isn't pinned is a no-op",
         %{user: user, quotes: [q | _]} do
      assert {:ok, true} = Users.remove_favorite_quote(user, q.id)
      assert Repo.get!(Quote, q.id).favorites_count == 0
    end

    test "favorites_count cannot underflow below zero",
         %{user: user, quotes: [q | _]} do
      # Manually nuke the counter so the floor guard has something to do.
      Repo.update_all(from(x in Quote, where: x.id == ^q.id), set: [favorites_count: 0])

      {:ok, true} = Users.add_favorite_quote(user, q.id)
      Repo.update_all(from(x in Quote, where: x.id == ^q.id), set: [favorites_count: 0])

      {:ok, true} = Users.remove_favorite_quote(user, q.id)
      assert Repo.get!(Quote, q.id).favorites_count == 0
    end
  end

  describe "update_user/2 with favorite_quotes (bulk replace)" do
    test "replaces the full list and renumbers positions to [0..n-1]",
         %{user: user, quotes: [q1, q2, q3 | _]} do
      {:ok, _} = Users.update_user(user, %{favorite_quotes: [q1.id, q2.id, q3.id]})

      pairs =
        from(qf in QuoteFavorite,
          where: qf.user_id == ^user.id,
          order_by: [asc: qf.position],
          select: {qf.position, qf.vn_quote_id}
        )
        |> Repo.all()

      assert pairs == [{0, q1.id}, {1, q2.id}, {2, q3.id}]
    end

    test "rejects with a length-validation changeset error when over limit",
         %{user: user, vn: vn} do
      limit = Kaguya.Users.User.quote_favorites_limit(user)
      quotes = for n <- 1..(limit + 1), do: insert_quote!(vn, "Bulk quote #{n} text body.")
      ids = Enum.map(quotes, & &1.id)
      assert {:error, changeset} = Users.update_user(user, %{favorite_quotes: ids})

      assert {_, opts} = changeset.errors[:favorite_quotes]
      assert opts[:validation] == :length
      assert opts[:kind] == :max
    end

    test "decrements counters for removed quotes, increments for newly added",
         %{user: user, quotes: [q1, q2, q3 | _]} do
      {:ok, _} = Users.update_user(user, %{favorite_quotes: [q1.id, q2.id]})
      {:ok, _} = Users.update_user(user, %{favorite_quotes: [q2.id, q3.id]})

      assert Repo.get!(Quote, q1.id).favorites_count == 0
      assert Repo.get!(Quote, q2.id).favorites_count == 1
      assert Repo.get!(Quote, q3.id).favorites_count == 1
    end
  end

  describe "cascade behavior" do
    test "deleting a quote removes pin rows referencing it",
         %{user: user, quotes: [q | _]} do
      {:ok, true} = Users.add_favorite_quote(user, q.id)
      {:ok, _} = Repo.delete(q)

      refute Repo.get_by(QuoteFavorite, user_id: user.id, vn_quote_id: q.id)
    end

    test "deleting a user removes their pin rows and decrements quote favorites_count",
         %{user: user, quotes: [q | _]} do
      other_user = UserFixtures.insert_user!()

      {:ok, true} = Users.add_favorite_quote(user, q.id)
      {:ok, true} = Users.add_favorite_quote(other_user, q.id)

      assert Repo.get!(Quote, q.id).favorites_count == 2

      {:ok, _} = Users.delete_user(user.id)

      refute Repo.get_by(QuoteFavorite, user_id: user.id, vn_quote_id: q.id)
      assert Repo.get!(Quote, q.id).favorites_count == 1
    end
  end

  # ─── helpers ──────────────────────────────────────────────────────────────

  defp insert_vn!() do
    suffix = :crypto.strong_rand_bytes(6) |> Base.url_encode64(padding: false)

    {:ok, vn} =
      %VisualNovel{}
      |> VisualNovel.changeset(%{title: "FavQuotes Test #{suffix}", original_language: "en"})
      |> Repo.insert()

    vn
  end

  defp insert_quote!(vn, text) do
    {:ok, q} =
      Kaguya.Characters.Quotes.create_quote(%{visual_novel_id: vn.id, quote: text})

    q
  end
end
