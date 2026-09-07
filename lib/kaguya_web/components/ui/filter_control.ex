defmodule KaguyaWeb.UI.FilterControl do
  @moduledoc """
  Shared presentation for filter triggers and their disclosure contents.

  Use these classes with `KaguyaWeb.UI.Menu` for popovers and `menu_item/1`
  for dismissing actions. Applied removable filters use `FilterChip`.
  These helpers do not add a second interaction implementation.
  """

  def trigger_class(active? \\ false, tone \\ :default) do
    base =
      "inline-flex h-9 shrink-0 cursor-pointer items-center justify-center gap-1.5 rounded-full border px-3.5 text-sm transition-colors duration-150 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-foreground-secondary data-[state=open]:border-foreground-tertiary data-[state=open]:bg-surface-elevated disabled:pointer-events-none disabled:opacity-50"

    base = base <> if(tone == :quiet, do: " font-normal", else: " font-medium")

    if active? do
      base <>
        " text-foreground-primary border-foreground-tertiary/50 bg-surface-elevated hover:border-foreground-secondary"
    else
      base <>
        if(tone == :quiet,
          do:
            " text-foreground-secondary border-border-divider/60 bg-surface-elevated/50 hover:border-foreground-tertiary/50 hover:bg-surface-elevated hover:text-foreground-primary",
          else:
            " text-foreground-primary border-border-divider bg-surface-elevated/50 hover:border-foreground-tertiary/50 hover:bg-surface-elevated"
        )
    end
  end

  def panel_class do
    "bg-surface-elevated border-border-divider flex flex-col rounded-xl border p-1 shadow-lg"
  end

  def option_class(selected? \\ false) do
    base =
      "flex min-h-9 w-full cursor-pointer items-center justify-between gap-2 rounded-md px-3 py-2 text-left text-sm transition-colors focus-visible:outline-2 focus-visible:outline-offset-[-2px] focus-visible:outline-foreground-secondary disabled:pointer-events-none disabled:opacity-50"

    if selected? do
      base <> " text-foreground-primary bg-foreground-primary/[0.06] font-medium"
    else
      base <>
        " text-foreground-secondary hover:bg-foreground-primary/[0.04] hover:text-foreground-primary"
    end
  end
end
