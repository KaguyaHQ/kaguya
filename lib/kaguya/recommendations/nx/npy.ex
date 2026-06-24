defmodule Kaguya.Recommendations.Nx.Npy do
  @moduledoc """
  Minimal NumPy `.npy` reader → `Nx.Tensor`.

  The B matrices the rec pipeline trains in Python are written as `.npy` files
  (contiguous f32 arrays, ~510 MB each). Rather than changing the training
  output format or shelling back out to Python, we read the file directly:
  the `.npy` format is public and stable (version 1.0/2.0/3.0).

  Format layout (https://numpy.org/doc/stable/reference/generated/numpy.lib.format.html):

      [6 bytes] magic  "\\x93NUMPY"
      [2 bytes] version  (major, minor)
      [2|4 bytes] header length  (2 for v1, 4 for v2+)
      [header_length bytes] header dict as Python literal, padded to 64 bytes
      [rest] raw array data

  We only support the subset we actually ship: row-major ("fortran_order: False"),
  dense float32/float64, 1D or 2D shapes. Throws on anything else — better to
  fail loud than silently misread.
  """

  @magic "\x93NUMPY"

  @doc """
  Read `path` into an `Nx.Tensor`. Uses `File.read!/1` which loads the entire
  buffer into memory — this is fine for the B matrices we hold in persistent
  term anyway (loaded once at boot).
  """
  def load!(path) do
    binary = File.read!(path)
    parse!(binary)
  end

  @doc false
  def parse!(<<@magic, major::8, minor::8, rest::binary>>) do
    header_len_bytes = if major >= 2, do: 4, else: 2

    <<header_len::little-integer-size(header_len_bytes)-unit(8), rest::binary>> = rest
    <<header_str::binary-size(header_len), data::binary>> = rest

    header = parse_header!(header_str)

    dtype =
      case header.descr do
        "<f4" -> {:f, 32}
        "<f8" -> {:f, 64}
        "<i4" -> {:s, 32}
        "<i8" -> {:s, 64}
        "|b1" -> {:u, 8}
        other -> raise "Npy: unsupported dtype #{inspect(other)} (got version #{major}.#{minor})"
      end

    if header.fortran_order do
      raise "Npy: fortran_order tensors not supported (expected C-order)"
    end

    Nx.from_binary(data, dtype) |> Nx.reshape(header.shape)
  end

  # Parse the header dict. It looks like:
  #   {'descr': '<f4', 'fortran_order': False, 'shape': (11273, 11273), }
  # Padded with spaces + \n. We only need three keys.
  defp parse_header!(str) do
    trimmed = String.trim(str)

    %{
      descr: extract_string(trimmed, "descr"),
      fortran_order: extract_bool(trimmed, "fortran_order"),
      shape: extract_shape(trimmed, "shape")
    }
  end

  defp extract_string(s, key) do
    # 'key': '<value>' — single quotes
    case Regex.run(~r/'#{key}':\s*'([^']+)'/, s) do
      [_, v] -> v
      _ -> raise "Npy: missing key #{key} in header: #{inspect(s)}"
    end
  end

  defp extract_bool(s, key) do
    case Regex.run(~r/'#{key}':\s*(True|False)/, s) do
      [_, "True"] -> true
      [_, "False"] -> false
      _ -> raise "Npy: missing key #{key} in header: #{inspect(s)}"
    end
  end

  defp extract_shape(s, key) do
    case Regex.run(~r/'#{key}':\s*\(([^)]*)\)/, s) do
      [_, inside] ->
        inside
        |> String.split(",", trim: true)
        |> Enum.map(&(&1 |> String.trim() |> String.to_integer()))
        |> List.to_tuple()

      _ ->
        raise "Npy: missing key #{key} in header: #{inspect(s)}"
    end
  end
end
