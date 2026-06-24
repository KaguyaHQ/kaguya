defmodule Kaguya.Utils do
  alias Kaguya.Repo
  import Ecto.Changeset

  @doc """
  Slugifies a title string.

  Options:

    * `:max_words` - limits the number of source words used (no limit by default)
    * `:truncate` - maximum slug length in characters (defaults to 45, preserving existing behavior)
    * `:separator` - separator passed through to `Slug.slugify/2`
  """
  def slugify_title(title, opts \\ []) when is_binary(title) do
    title =
      case Keyword.get(opts, :max_words) do
        nil ->
          title

        max_words when is_integer(max_words) and max_words > 0 ->
          title
          |> String.split(~r/\s+/u, trim: true)
          |> Enum.take(max_words)
          |> Enum.join(" ")

        _ ->
          title
      end

    slug_opts =
      opts
      |> Keyword.take([:separator, :truncate])
      |> Keyword.put_new(:truncate, 45)

    Slug.slugify(title, slug_opts)
  end

  @doc """
  Generates a unique slug for the given title by checking for conflicts
  in the provided schema module. Accepts an optional keyword list to scope the query,
  for example by `user_id` for shelves.

  When `:release_date` is provided and a collision is found, tries `base-year`
  before falling back to `base-year-1`, `base-year-2`, etc.
  """
  def generate_unique_slug(title, module, opts \\ []) do
    base_slug = slugify_title(title, opts)
    scope = build_scope(opts)

    if slug_available?(base_slug, module, scope) do
      base_slug
    else
      release_date = Keyword.get(opts, :release_date)

      if release_date do
        year = if is_struct(release_date, Date), do: release_date.year, else: release_date
        year_slug = "#{base_slug}-#{year}"

        if slug_available?(year_slug, module, scope) do
          year_slug
        else
          find_numeric_slug(year_slug, module, 1, scope)
        end
      else
        find_numeric_slug(base_slug, module, 1, scope)
      end
    end
  end

  defp slug_available?(slug, module, scope) do
    Repo.get_by(module, [slug: slug] ++ scope) == nil
  end

  defp find_numeric_slug(prefix, module, n, scope) do
    slug = "#{prefix}-#{n}"

    if slug_available?(slug, module, scope) do
      slug
    else
      find_numeric_slug(prefix, module, n + 1, scope)
    end
  end

  defp build_scope(opts) do
    case Keyword.get(opts, :user_id) do
      nil -> []
      user_id -> [user_id: user_id]
    end
  end

  @doc """
  Generates and sets a unique slug on the changeset using the value from `source_field`.
  Accepts optional options (like scoping by :user_id). If no user_id is explicitly passed in opts,
  it will try to fetch it from the changeset.

  Slugs are stable: once an entity has a slug, editing the source field (e.g.
  the VN title) does NOT regenerate it. URLs that link to the old slug stay
  valid forever. Slugs are only generated on creation, when the existing
  slug is empty/nil, or when the caller explicitly clears it via the
  changeset.
  """
  def put_unique_slug(changeset, source_field, opts \\ []) do
    current_slug = get_field(changeset, :slug)

    if current_slug in [nil, ""] do
      title = get_change(changeset, source_field) || get_field(changeset, source_field)

      if title do
        # Determine the module from the changeset data
        module = changeset.data.__struct__
        # Merge :user_id from changeset if not explicitly passed.
        opts = Keyword.put_new(opts, :user_id, get_field(changeset, :user_id))

        # Use release_date for year-based slug suffixes when available
        release_date = changeset.changes[:release_date] || Map.get(changeset.data, :release_date)
        opts = if release_date, do: Keyword.put_new(opts, :release_date, release_date), else: opts

        unique_slug = generate_unique_slug(title, module, opts)
        put_change(changeset, :slug, unique_slug)
      else
        changeset
      end
    else
      # Slug already set — never auto-regenerate. URLs stay stable.
      changeset
    end
  end
end

defmodule Kaguya.SentryFinchClient do
  @behaviour Sentry.HTTPClient

  @impl true
  def child_spec do
    Supervisor.child_spec({Finch, name: __MODULE__}, id: __MODULE__)
  end

  @impl true
  def post(url, headers, body) do
    request = Finch.build(:post, url, headers, body)

    case Finch.request(request, __MODULE__) do
      {:ok, %Finch.Response{status: status, headers: headers, body: body}} ->
        {:ok, status, headers, body}

      {:error, error} ->
        {:error, error}
    end
  end
end

defmodule Kaguya.Utils.TextPreview do
  @moduledoc "Helpers for extracting and truncating text from various content formats."

  @doc """
  Extracts plain text from a string or list of strings.

  Returns a flat string.
  """
  def extract_text(s) when is_binary(s), do: s

  def extract_text(list) when is_list(list) do
    Enum.map_join(list, " ", &extract_text/1)
  end

  def extract_text(_), do: ""

  @doc """
  Truncates at word boundaries to the given limit, appending "..." if needed.
  """
  def truncate_on_words(text, limit \\ 150) when is_binary(text) do
    if String.length(text) <= limit do
      text
    else
      text
      |> String.split(" ")
      |> Enum.reduce_while("", fn word, acc ->
        candidate = if acc == "", do: word, else: acc <> " " <> word
        if String.length(candidate) > limit, do: {:halt, acc <> "..."}, else: {:cont, candidate}
      end)
    end
  end
end
