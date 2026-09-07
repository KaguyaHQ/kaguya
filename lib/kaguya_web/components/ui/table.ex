defmodule KaguyaWeb.UI.Table do
  @moduledoc """
  Semantic table presentation for server-rendered collections.

  Callers own columns, responsive visibility, data, and sorting. The primitives
  share readable typography, restrained separators, and keyboard focus styles
  without introducing client-side table state.
  """
  use KaguyaWeb, :ui_component

  attr :id, :string, required: true
  attr :caption, :string, required: true
  attr :class, :any, default: nil
  slot :header, required: true
  slot :inner_block, required: true

  def table(assigns) do
    ~H"""
    <table id={@id} class={["w-full table-fixed text-left text-sm", @class]}>
      <caption class="sr-only">{@caption}</caption>
      <thead class="bg-surface-elevated/70 border-border-divider text-foreground-secondary border-y">
        <tr>{render_slot(@header)}</tr>
      </thead>
      <tbody class="[&>tr:focus-within]:bg-surface-elevated/60 [&>tr:hover]:bg-surface-elevated/60 [&>tr]:border-border-divider/50 [&>tr]:border-b [&>tr]:transition-colors [&>tr:last-child]:border-b-0">
        {render_slot(@inner_block)}
      </tbody>
    </table>
    """
  end

  attr :class, :any, default: nil
  attr :sort, :string, values: ~w(none ascending descending), default: "none"
  slot :inner_block, required: true

  def column_header(assigns) do
    ~H"""
    <th scope="col" aria-sort={if @sort != "none", do: @sort} class={["py-3 font-medium", @class]}>
      {render_slot(@inner_block)}
    </th>
    """
  end

  attr :id, :string, required: true
  attr :patch, :string, required: true
  attr :label, :string, required: true
  attr :sort, :string, values: ~w(none ascending descending), default: "none"
  attr :next_direction, :string, values: ~w(ascending descending), required: true
  attr :align, :string, values: ~w(start end), default: "start"

  def sort_link(assigns) do
    ~H"""
    <.link
      id={@id}
      patch={@patch}
      aria-label={"Sort by #{@label}, #{@next_direction}"}
      class={[
        "group/sort hover:text-foreground-primary inline-flex min-h-6 items-center gap-1.5 rounded-sm whitespace-nowrap transition-colors focus-visible:outline-2 focus-visible:outline-offset-4",
        @sort != "none" && "text-foreground-primary",
        @align == "end" && "flex-row-reverse"
      ]}
    >
      {@label}<span
        aria-hidden="true"
        class={[
          "inline-flex w-3 justify-center text-xs",
          @sort == "none" && "invisible group-hover/sort:visible group-focus-visible/sort:visible"
        ]}
      >{if @sort == "ascending" or (@sort == "none" and @next_direction == "ascending"),
        do: "↑",
        else: "↓"}</span>
    </.link>
    """
  end
end
