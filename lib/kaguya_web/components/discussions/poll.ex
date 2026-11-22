defmodule KaguyaWeb.Components.Discussions.Poll do
  @moduledoc """
  A discussion post's poll. Before voting, options are buttons; after voting
  (or when voting isn't possible) each shows its share of the votes. Clicking
  another option changes the vote.

  The parent handles `vote_event` with `"post-id"` and `"option-id"` params.
  """

  use KaguyaWeb, :html

  attr :id, :string, required: true
  attr :poll, :map, required: true
  attr :post_id, :string, required: true
  attr :vote_event, :string, required: true
  attr :can_vote, :boolean, default: false
  attr :signed_in, :boolean, default: false
  attr :class, :any, default: nil

  def poll(assigns) do
    assigns =
      assign(assigns, :show_results, assigns.poll.my_option_id != nil or not assigns.can_vote)

    ~H"""
    <div id={@id} role="group" aria-label="Poll" class={["relative z-10 space-y-1.5", @class]}>
      <.poll_option
        :for={option <- @poll.options}
        id={"#{@id}-option-#{option.id}"}
        option={option}
        total={@poll.total_votes}
        mine={option.id == @poll.my_option_id}
        show_results={@show_results}
        can_vote={@can_vote}
        vote_event={@vote_event}
        post_id={@post_id}
      />
      <p class="text-foreground-tertiary pt-0.5 text-xs tabular-nums">
        {vote_count(@poll.total_votes)}<span :if={!@signed_in}> · Sign in to vote</span><span :if={
          @can_vote && @poll.my_option_id
        }> · You can change your vote</span>
      </p>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :option, :map, required: true
  attr :total, :integer, required: true
  attr :mine, :boolean, required: true
  attr :show_results, :boolean, required: true
  attr :can_vote, :boolean, required: true
  attr :vote_event, :string, required: true
  attr :post_id, :string, required: true

  defp poll_option(assigns) do
    assigns = assign(assigns, :percent, percent(assigns.option.votes, assigns.total))

    ~H"""
    <button
      :if={@can_vote}
      id={@id}
      type="button"
      phx-click={@vote_event}
      phx-value-post-id={@post_id}
      phx-value-option-id={@option.id}
      aria-pressed={to_string(@mine)}
      class={[
        "group/poll block w-full rounded-md border text-left transition-colors",
        if(@mine,
          do: "border-white/25",
          else: "border-white/10 hover:border-white/20 hover:bg-white/3"
        )
      ]}
    >
      <.option_body option={@option} percent={@percent} mine={@mine} show_results={@show_results} />
    </button>
    <div :if={!@can_vote} id={@id} class="rounded-md border border-white/10">
      <.option_body option={@option} percent={@percent} mine={@mine} show_results={@show_results} />
    </div>
    """
  end

  attr :option, :map, required: true
  attr :percent, :integer, required: true
  attr :mine, :boolean, required: true
  attr :show_results, :boolean, required: true

  defp option_body(assigns) do
    ~H"""
    <span class="relative flex min-h-9 items-center justify-between gap-3 overflow-hidden rounded-[5px] px-3 py-1.5 text-sm">
      <span
        :if={@show_results}
        class={[
          "absolute inset-y-0 left-0 transition-[width] duration-500 ease-out",
          if(@mine, do: "bg-white/14", else: "bg-white/6")
        ]}
        style={"width: #{@percent}%"}
        aria-hidden="true"
      ></span>
      <span class="text-foreground-primary relative flex min-w-0 items-center gap-2">
        <Lucide.check :if={@mine} class="size-3.5 shrink-0" aria-label="Your vote" />
        <span class={["wrap-break-word", @mine && "font-medium"]}>{@option.label}</span>
      </span>
      <span
        :if={@show_results}
        class="text-foreground-secondary relative shrink-0 text-xs tabular-nums"
      >
        {@percent}%
      </span>
    </span>
    """
  end

  defp percent(_votes, 0), do: 0
  defp percent(votes, total), do: round(votes * 100 / total)

  defp vote_count(1), do: "1 vote"
  defp vote_count(count), do: "#{count} votes"
end
