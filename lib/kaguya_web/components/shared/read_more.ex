defmodule KaguyaWeb.SharedComponents.ReadMore do
  @moduledoc """
  Client-toggled "read more" wrapper — Phoenix-side port of
  `../personal/legacy-next-app/src/components/shared/ReadMoreText.tsx` (+ DescriptionReadMore).

  Renders the full body inside a CSS line-clamp container. A JS hook
  (`ReadMore`, defined in `assets/js/hooks/read_more.js`) measures
  whether content actually overflows on mount; if it does, it shows the
  toggle button. Toggling adds/removes a single class — no LiveView
  round-trip, so it feels instant.

  Why client-measured (not server-truncated):
    * SEO — the full body is in the initial HTML.
    * UX — the toggle is instant; LV would re-render the whole block.
    * Resilience — JS-disabled visitors see the full body (just no toggle).

  See `docs/migrations/nextjs-liveview/plans/component-parity-plan.md` § 4.

  ## Example

      <.read_more id={"vn-\#{@vn.id}-desc"} lines={6}>
        <div class="kaguya-markdown">
          {raw(@vn.description)}
        </div>
      </.read_more>
  """

  use KaguyaWeb, :html

  attr :id, :string, required: true, doc: "Stable DOM id for the JS hook."

  attr :lines, :integer,
    default: 6,
    doc: "Number of lines to clamp to when collapsed."

  attr :expand_label, :string, default: "Read more"
  attr :collapse_label, :string, default: "Show less"
  attr :class, :any, default: nil, doc: "Classes for the inner content wrapper."

  attr :button_class, :any,
    default:
      "mt-2 inline-flex items-center text-sm font-medium text-[rgb(var(--foreground-link))] hover:underline",
    doc: "Classes for the toggle button."

  attr :rest, :global

  slot :inner_block, required: true

  def read_more(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="ReadMore"
      data-readmore
      data-expanded="false"
      style={"--readmore-lines: #{@lines};"}
      {@rest}
    >
      <div data-readmore-content class={["readmore-collapsed", @class]}>
        {render_slot(@inner_block)}
      </div>
      <button
        type="button"
        data-readmore-toggle
        data-expand-label={@expand_label}
        data-collapse-label={@collapse_label}
        class={[@button_class, "hidden"]}
      >
        {@expand_label}
      </button>
    </div>
    """
  end
end
