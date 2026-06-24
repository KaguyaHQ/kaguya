defmodule KaguyaWeb.ErrorJSON do
  def render("500.json", _assigns) do
    %{error: "Internal Server Error"}
  end

  def render("404.json", _assigns) do
    %{error: "Not Found"}
  end

  def render(_template, _assigns) do
    %{error: "Unknown Error"}
  end
end
