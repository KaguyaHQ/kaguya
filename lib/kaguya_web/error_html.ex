defmodule KaguyaWeb.ErrorHTML do
  @moduledoc """
  Phoenix error-formatter for HTML responses.

  The 404 template renders `KaguyaWeb.Components.Shared.NotFoundPage`, the
  same component used inside LiveViews when a resource is missing — so a
  direct visit to an unmatched URL and an in-app navigation to a missing
  resource look identical. Other status codes fall back to Phoenix's
  default status-message text; we can flesh those out as needed.
  """

  use KaguyaWeb, :html

  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
