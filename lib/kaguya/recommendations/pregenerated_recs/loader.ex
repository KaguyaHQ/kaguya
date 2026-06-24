defmodule Kaguya.Recommendations.PregeneratedRecs.Loader do
  @moduledoc """
  Boot-time loader for the pre-generated top-K EASE recommendations.

  Reads two files produced by `priv/recommendations/pregenerate_user_recs.py`:

    * `pregenerated_recs.bin`  — per-uid packed recs (top-K + pref_count)
    * `vndb_username_lookup.bin` — global username -> uid index, usernames
      lowercased at generation time so lookups are case-insensitive without
      a downcase per request.

  Both files start with a 4-byte magic + 1-byte version header. The
  loader refuses any other framing rather than misinterpreting a file
  that happens to decode into plausible-looking bytes.

  Both are parsed once at startup into two named ETS tables:

    * `:pregenerated_user_recs`     — uid -> {pref_count, [rec_map, ...]}
    * `:pregenerated_username_index` — lowercased_username -> uid

  Each rec_map: `%{vndb_id, score, total_positive_contribution, reasons}`.

  If either file is missing (dev env that hasn't imported a snapshot yet,
  or a deploy rolled out before the next Python run), or malformed, we
  log a warning and continue with empty tables. Every lookup then returns
  `:not_found` / `:not_pregenerated` so callers can surface a clean error
  rather than crashing the supervisor.

  Snapshots can be swapped without a full app restart via:

      GenServer.call(#{inspect(__MODULE__)}, :reload)

  Supervision: blocks `init/1` until parsing completes.
  """

  use GenServer
  require Logger

  @recs_table :pregenerated_user_recs
  @username_table :pregenerated_username_index

  @recs_filename "pregenerated_recs.bin"
  @username_filename "vndb_username_lookup.bin"
  @meta_filename "pregenerated_recs_meta.json"

  # Must match the Python writer constants in
  # `priv/recommendations/pregenerate_user_recs.py`.
  @recs_magic "KGPR"
  @username_magic "KGUL"
  @file_version 1

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    create_table(@recs_table)
    create_table(@username_table)

    root = model_root()

    load_recs(Path.join(root, @recs_filename))
    load_usernames(Path.join(root, @username_filename))
    log_meta(Path.join(root, @meta_filename))

    {:ok, %{root: root}}
  end

  @impl true
  def handle_call(:reload, _from, state) do
    root = Map.get(state, :root) || model_root()

    try do
      # Truncate both tables inside the call; the per-file loaders also
      # truncate on parse failure so a partially-populated table is
      # never visible to readers.
      :ets.delete_all_objects(@recs_table)
      :ets.delete_all_objects(@username_table)

      load_recs(Path.join(root, @recs_filename))
      load_usernames(Path.join(root, @username_filename))
      log_meta(Path.join(root, @meta_filename))

      {:reply, :ok, %{state | root: root}}
    rescue
      e ->
        Logger.warning("[PregeneratedRecs.Loader] reload failed: #{Exception.message(e)}")

        {:reply, {:error, Exception.message(e)}, state}
    end
  end

  defp model_root do
    System.get_env("KAGUYA_MODEL_DIR") || Application.app_dir(:kaguya, "priv/data")
  end

  defp create_table(name) do
    case :ets.info(name) do
      :undefined ->
        :ets.new(name, [:set, :protected, :named_table, read_concurrency: true])

      _ ->
        :ets.delete_all_objects(name)
        name
    end
  end

  # ---------------------------------------------------------------------------
  # Recs file
  # ---------------------------------------------------------------------------

  defp load_recs(path) do
    if File.exists?(path) do
      t0 = System.monotonic_time(:millisecond)
      bin = File.read!(path)

      try do
        parse_recs(bin)
        n = :ets.info(@recs_table, :size) || 0
        bytes = byte_size(bin)
        elapsed = System.monotonic_time(:millisecond) - t0

        Logger.info(
          "[PregeneratedRecs.Loader] loaded #{n} users from #{@recs_filename} " <>
            "(#{format_mb(bytes)} on disk) in #{elapsed}ms"
        )
      rescue
        e ->
          Logger.warning(
            "[PregeneratedRecs.Loader] failed to parse #{@recs_filename}: " <>
              "#{Exception.message(e)} — starting with empty lookup"
          )

          :ets.delete_all_objects(@recs_table)
      catch
        kind, reason ->
          Logger.warning(
            "[PregeneratedRecs.Loader] failed to parse #{@recs_filename}: " <>
              "#{inspect({kind, reason})} — starting with empty lookup"
          )

          :ets.delete_all_objects(@recs_table)
      end
    else
      Logger.warning(
        "[PregeneratedRecs.Loader] #{@recs_filename} not found at #{path} — " <>
          "recommend/2 calls will return :not_pregenerated. " <>
          "Run priv/recommendations/pregenerate_user_recs.py to populate."
      )
    end
  end

  defp parse_recs(
         <<@recs_magic, @file_version::unsigned-8, _n_users::big-unsigned-32, rest::binary>>
       ) do
    walk_recs(rest)
  end

  defp parse_recs(<<magic::binary-size(4), version::unsigned-8, _::binary>>) do
    raise "unexpected header: magic=#{inspect(magic)} version=#{version} " <>
            "(expected #{inspect(@recs_magic)} v#{@file_version})"
  end

  defp parse_recs(_),
    do: raise("truncated header (file too short to contain magic+version+n_users)")

  defp walk_recs(<<>>), do: :ok

  defp walk_recs(
         <<uid_len::unsigned-8, uid::binary-size(uid_len), pref_count::big-unsigned-16,
           n_recs::big-unsigned-16, rest::binary>>
       ) do
    {recs, tail} = decode_recs(rest, n_recs, [])
    :ets.insert(@recs_table, {uid, {pref_count, recs}})
    walk_recs(tail)
  end

  # Per-rec: <vid_len><vid><score><total_positive><n_reasons>[<rid_len><rid><contrib>]*
  defp decode_recs(rest, 0, acc), do: {Enum.reverse(acc), rest}

  defp decode_recs(
         <<vid_len::unsigned-8, vid::binary-size(vid_len), score::big-float-32,
           total_positive::big-float-32, n_reasons::unsigned-8, rest::binary>>,
         remaining,
         acc
       ) do
    {reasons, after_reasons} = decode_reasons(rest, n_reasons, [])

    rec = %{
      vndb_id: vid,
      score: score,
      total_positive_contribution: total_positive,
      reasons: reasons
    }

    decode_recs(after_reasons, remaining - 1, [rec | acc])
  end

  defp decode_reasons(rest, 0, acc), do: {Enum.reverse(acc), rest}

  # Per-reason layout:
  #   <rid_len:u8> <rid> <contrib:f32> <vote:u8> <label_id:u8>
  #
  # Exactly one of (vote, label_id) is nonzero:
  #   vote ∈ {10..100}: VNDB vote on the source VN (1.0-10.0 displayed).
  #   label_id ∈ {1..5}: VNDB label id (1=Playing, 2=Finished, 3=On hold,
  #     4=Dropped, 5=Wishlist). `PregeneratedRecs.hydrate_reasons/2` maps
  #     these to the frontend's user_rating / user_status fields so guest
  #     tooltips match the "Because they rated X N★" / status inline text
  #     logged-in users get.
  defp decode_reasons(
         <<rid_len::unsigned-8, rid::binary-size(rid_len), contrib::big-float-32,
           vote::unsigned-8, label_id::unsigned-8, rest::binary>>,
         remaining,
         acc
       ) do
    reason = %{
      vndb_id: rid,
      contribution: contrib,
      vote: vote,
      label_id: label_id
    }

    decode_reasons(rest, remaining - 1, [reason | acc])
  end

  # ---------------------------------------------------------------------------
  # Username index file
  # ---------------------------------------------------------------------------

  defp load_usernames(path) do
    if File.exists?(path) do
      t0 = System.monotonic_time(:millisecond)
      bin = File.read!(path)

      try do
        parse_usernames(bin)
        n = :ets.info(@username_table, :size) || 0
        bytes = byte_size(bin)
        elapsed = System.monotonic_time(:millisecond) - t0

        Logger.info(
          "[PregeneratedRecs.Loader] loaded #{n} usernames from #{@username_filename} " <>
            "(#{format_mb(bytes)} on disk) in #{elapsed}ms"
        )
      rescue
        e ->
          Logger.warning(
            "[PregeneratedRecs.Loader] failed to parse #{@username_filename}: " <>
              "#{Exception.message(e)} — starting with empty lookup"
          )

          :ets.delete_all_objects(@username_table)
      catch
        kind, reason ->
          Logger.warning(
            "[PregeneratedRecs.Loader] failed to parse #{@username_filename}: " <>
              "#{inspect({kind, reason})} — starting with empty lookup"
          )

          :ets.delete_all_objects(@username_table)
      end
    else
      Logger.warning(
        "[PregeneratedRecs.Loader] #{@username_filename} not found at #{path} — " <>
          "username lookups will return :not_found."
      )
    end
  end

  defp parse_usernames(
         <<@username_magic, @file_version::unsigned-8, _n_users::big-unsigned-32, rest::binary>>
       ) do
    walk_usernames(rest)
  end

  defp parse_usernames(<<magic::binary-size(4), version::unsigned-8, _::binary>>) do
    raise "unexpected header: magic=#{inspect(magic)} version=#{version} " <>
            "(expected #{inspect(@username_magic)} v#{@file_version})"
  end

  defp parse_usernames(_),
    do: raise("truncated header (file too short to contain magic+version+n_users)")

  defp walk_usernames(<<>>), do: :ok

  defp walk_usernames(
         <<uid_len::unsigned-8, uid::binary-size(uid_len), uname_len::big-unsigned-16,
           uname::binary-size(uname_len), rest::binary>>
       ) do
    :ets.insert(@username_table, {uname, uid})
    walk_usernames(rest)
  end

  # ---------------------------------------------------------------------------
  # Meta — purely informational
  # ---------------------------------------------------------------------------

  defp log_meta(path) do
    with true <- File.exists?(path),
         {:ok, bin} <- File.read(path),
         {:ok, meta} <- Jason.decode(bin) do
      Logger.info(
        "[PregeneratedRecs.Loader] snapshot meta: built_at=#{inspect(meta["built_at"])} " <>
          "n_users_scored=#{inspect(meta["n_users_scored"])} " <>
          "n_users_total=#{inspect(meta["n_users_total"])} " <>
          "model_version=#{inspect(meta["model_version"])} " <>
          "source_dump_date=#{inspect(meta["source_dump_date"])}"
      )
    else
      _ -> :ok
    end
  end

  defp format_mb(bytes) when is_integer(bytes) do
    :io_lib.format("~.2fMB", [bytes / (1024 * 1024)]) |> IO.iodata_to_binary()
  end
end
