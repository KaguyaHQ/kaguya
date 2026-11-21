defmodule Kaguya.Sync.NukigeClassifierTest do
  use ExUnit.Case, async: true

  alias Kaguya.Repo
  alias Kaguya.Sync.DumpSync

  setup do
    source =
      start_supervised!(
        {Postgrex,
         Keyword.take(Repo.config(), [:hostname, :port, :username, :password, :database])}
      )

    for definition <- [
          "tags_vn (vid text, tag text, uid text, vote smallint, ignore boolean)",
          "vn (id text, c_votecount integer, c_image text, description text)",
          "images (id text, c_sexual_avg smallint, c_votecount integer)"
        ] do
      Postgrex.query!(source, "CREATE TEMP TABLE " <> definition, [])
    end

    %{source: source}
  end

  test "exactly 75% at the minimum weight survives repeating-decimal vote averages", %{
    source: source
  } do
    add_vn(source, "v90000001", [
      {"g214", [3, 3, 1, 1, 1, 1, 1, 1, 1, 1, 1]},
      {"g147", [3, 1, 1]}
    ])

    add_vn(source, "v90000002", [{"g214", [3, 3, 3, 3, 2]}, {"g147", [3, 3]}])
    add_vn(source, "v90000003", [{"g214", [3, 3, 3, 3, 3, 3, 1]}])

    assert DumpSync.classify_nukige_from_dump(source) == MapSet.new(["v90000001"])
  end

  test "negative votes reduce the evidence and ignored votes do not contribute", %{source: source} do
    add_vn(source, "v90000004", [{"g214", [3, 3, 3, 3, 3, 3, 2, -1]}])
    add_vn(source, "v90000005", [{"g214", [3, 3, 3, 3, 3, 3, 2]}])

    Postgrex.query!(source, "INSERT INTO tags_vn VALUES ($1, 'g147', 'ignored', 3, true)", [
      "v90000005"
    ])

    assert DumpSync.classify_nukige_from_dump(source) == MapSet.new(["v90000005"])
  end

  test "the legacy bestiality rule resolves tied voter counts by numeric tag ID", %{
    source: source
  } do
    add_vn(source, "v90000006", [{"g183", [1]}, {"g2", [1]}])
    add_vn(source, "v90000007", [{"g183", [1]}, {"g1900", [1]}])

    assert DumpSync.classify_nukige_from_dump(source) == MapSet.new(["v90000007"])
  end

  defp add_vn(source, id, tags) do
    Postgrex.query!(source, "INSERT INTO vn VALUES ($1, 1, NULL, 'Has a description')", [id])

    for {tag, votes} <- tags, {vote, index} <- Enum.with_index(votes) do
      Postgrex.query!(source, "INSERT INTO tags_vn VALUES ($1, $2, $3, $4, false)", [
        id,
        tag,
        "u#{index}",
        vote
      ])
    end
  end
end
