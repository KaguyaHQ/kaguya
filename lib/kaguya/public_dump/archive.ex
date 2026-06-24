defmodule Kaguya.PublicDump.Archive do
  @moduledoc """
  Bundles the staging directory into a `.tar.zst` (or `.tar.gz` if zstd
  isn't installed). Mirrors VNDB's `tar -cf … -I 'zstd -7'` invocation
  (`dbdump.pl:348`).
  """

  require Logger

  @doc """
  Bundle `staging_dir` into an archive at `output_path`. Returns the final
  path with the correct extension applied.
  """
  def create(staging_dir, output_path) do
    {kind, ext} =
      if System.find_executable("zstd"), do: {:zstd, ".zst"}, else: {:gzip, ".gz"}

    final_path = ensure_ext(output_path, ext)

    cmd = build_cmd(kind, staging_dir, final_path)
    Logger.info("Bundling: #{cmd}")

    case System.shell(cmd, stderr_to_stdout: true) do
      {_, 0} ->
        Logger.info("Archive: #{final_path}")
        {:ok, final_path}

      {output, code} ->
        raise "tar/compress failed (exit #{code}):\n#{output}"
    end
  end

  defp build_cmd(:zstd, staging, out) do
    # `-f` so re-runs overwrite any existing archive (idempotent).
    "tar -cf - -C #{esc(staging)} . | zstd -7 -f -o #{esc(out)}"
  end

  defp build_cmd(:gzip, staging, out) do
    "tar -czf #{esc(out)} -C #{esc(staging)} ."
  end

  defp esc(path), do: "\"" <> String.replace(path, "\"", "\\\"") <> "\""

  defp ensure_ext(path, ext) do
    cond do
      String.ends_with?(path, ".tar" <> ext) -> path
      String.ends_with?(path, ".tar.zst") -> String.replace_suffix(path, ".zst", ext)
      String.ends_with?(path, ".tar.gz") -> String.replace_suffix(path, ".gz", ext)
      String.ends_with?(path, ".tar") -> path <> ext
      true -> path <> ".tar" <> ext
    end
  end
end
