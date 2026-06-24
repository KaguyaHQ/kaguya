defmodule Kaguya.Uploads.Helpers.VndbXmlParser do
  @moduledoc """
  Parses VNDB XML export files using SweetXml.

  Expected structure:
  ```xml
  <vndb-export version="1.0" date="...">
    <user><name>...</name><url>...</url></user>
    <labels><label id="1" label="Playing" private="false" />...</labels>
    <vns>
      <vn id="v123" private="false">
        <title original="...">Title</title>
        <label id="2" label="Finished" />
        <added>2025-01-01T00:00:00Z</added>
        <modified>2025-01-02T00:00:00Z</modified>
        <vote timestamp="2025-01-02T00:00:00Z">8</vote>
        <started>2025-01-01</started>
        <finished>2025-01-02</finished>
        <notes>User notes here</notes>
      </vn>
    </vns>
    <reviews>
      <review id="w123" spoiler="false">
        <vn id="v123">Title</vn>
        <added>2025-01-01T00:00:00Z</added>
        <modified>2025-01-02T00:00:00Z</modified>
        <text>Review content...</text>
      </review>
    </reviews>
  </vndb-export>
  ```
  """

  import SweetXml

  @doc """
  Parses VNDB XML content and returns a map with labels, vns, and reviews.

  XML is parsed with `dtd: :none` to disable both internal and external entity
  expansion — this prevents billion-laughs and XXE attacks regardless of file
  size. See SweetXml's `parse/2` docs (Security section).
  """
  def parse(xml_content) do
    result =
      xml_content
      |> sanitize_xml()
      |> SweetXml.parse(dtd: :none, quiet: true)
      |> xmap(
        export_version: ~x"/vndb-export/@version"s,
        export_date: ~x"/vndb-export/@date"s,
        labels: [
          ~x"/vndb-export/labels/label"l,
          id: ~x"./@id"s |> transform_by(&parse_int/1),
          name: ~x"./@label"s,
          private: ~x"./@private"s |> transform_by(&parse_bool/1)
        ],
        vns: [
          ~x"/vndb-export/vns/vn"l,
          vndb_id: ~x"./@id"s,
          private: ~x"./@private"s |> transform_by(&parse_bool/1),
          title: ~x"./title/text()"s |> transform_by(&String.trim/1),
          title_original: ~x"./title/@original"s,
          labels: [
            ~x"./label"l,
            id: ~x"./@id"s |> transform_by(&parse_int/1),
            name: ~x"./@label"s
          ],
          added: ~x"./added/text()"s,
          modified: ~x"./modified/text()"s,
          vote: ~x"./vote/text()"s,
          vote_timestamp: ~x"./vote/@timestamp"s,
          started: ~x"./started/text()"s,
          finished: ~x"./finished/text()"s,
          notes: ~x"./notes/text()"s |> transform_by(&trim_or_nil/1)
        ],
        reviews: [
          ~x"/vndb-export/reviews/review"l,
          review_id: ~x"./@id"s,
          spoiler: ~x"./@spoiler"s |> transform_by(&parse_bool/1),
          vndb_id: ~x"./vn/@id"s,
          vn_title: ~x"./vn/text()"s,
          added: ~x"./added/text()"s,
          modified: ~x"./modified/text()"s,
          text: ~x"./text/text()"s |> transform_by(&trim_or_nil/1)
        ]
      )

    {:ok, result}
  rescue
    e -> {:error, "Failed to parse XML file: #{Exception.message(e)}"}
  catch
    :exit, reason -> {:error, "Failed to parse XML file: #{inspect(reason)}"}
  end

  # Escape bare & characters that aren't already part of an XML entity
  defp sanitize_xml(xml) do
    Regex.replace(~r/&(?!(?:amp|lt|gt|apos|quot|#\d+|#x[\da-fA-F]+);)/, xml, "&amp;")
  end

  defp parse_int(""), do: nil
  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_bool("true"), do: true
  defp parse_bool("false"), do: false
  defp parse_bool(_), do: false

  defp trim_or_nil(nil), do: nil
  defp trim_or_nil(""), do: nil

  defp trim_or_nil(str) when is_binary(str) do
    trimmed = String.trim(str)
    if trimmed == "", do: nil, else: trimmed
  end
end
