defmodule KaguyaWeb.Components.Profile.Skeletons do
  @moduledoc """
  Header + content placeholders shown while a profile route is loading.

  Mirrors `ProfileHeaderSkeleton.tsx` and `ProfileContentSkeleton.tsx`.
  Used by tabs that pre-render before their full view-model has loaded.
  """

  use KaguyaWeb, :html

  def header_skeleton(assigns) do
    ~H"""
    <section class="col-span-full lg:mx-auto lg:max-w-[988px]">
      <div class="max-lg:flex max-lg:flex-col max-lg:items-center">
        <div class="relative max-lg:w-full lg:overflow-hidden">
          <div class="h-[156px] w-full animate-pulse bg-[rgb(var(--surface-elevated))] lg:h-[196px]" />
        </div>
        <div class="mx-auto w-full px-4 max-lg:-mt-11 lg:px-6">
          <div class="flex items-center max-lg:flex-col lg:space-x-4">
            <div class="relative z-20 size-[90px] animate-pulse rounded-full bg-[rgb(var(--surface-elevated))] shadow-[0_0_0_5px_rgb(var(--surface-base))] max-lg:self-start lg:-mt-[50px] lg:size-[100px]" />
            <div class="flex flex-1 flex-col gap-3 max-lg:mt-4 lg:flex-row lg:items-center lg:justify-between">
              <div class="flex flex-col gap-2">
                <div class="h-6 w-40 animate-pulse rounded bg-[rgb(var(--surface-elevated))]" />
                <div class="h-4 w-24 animate-pulse rounded bg-[rgb(var(--surface-elevated))]" />
              </div>
              <div class="flex items-center gap-6">
                <div
                  :for={_ <- 1..4}
                  class="h-10 w-12 animate-pulse rounded bg-[rgb(var(--surface-elevated))]"
                />
              </div>
            </div>
          </div>
        </div>
      </div>
      <div class="mt-5 hidden h-12 w-full max-w-[988px] animate-pulse bg-[rgb(var(--surface-elevated))]/60 lg:block" />
    </section>
    """
  end

  def content_skeleton(assigns) do
    ~H"""
    <div class="mx-auto mt-8 max-w-[988px] px-4 lg:mt-10">
      <div class="grid gap-6 lg:grid-cols-[minmax(0,652px)_1fr] lg:gap-20">
        <div class="flex flex-col gap-6">
          <div class="h-32 w-full animate-pulse rounded bg-[rgb(var(--surface-elevated))]/60" />
          <div class="h-48 w-full animate-pulse rounded bg-[rgb(var(--surface-elevated))]/60" />
          <div class="h-48 w-full animate-pulse rounded bg-[rgb(var(--surface-elevated))]/60" />
        </div>
        <div class="hidden flex-col gap-6 lg:flex">
          <div class="h-48 w-full animate-pulse rounded bg-[rgb(var(--surface-elevated))]/60" />
          <div class="h-32 w-full animate-pulse rounded bg-[rgb(var(--surface-elevated))]/60" />
        </div>
      </div>
    </div>
    """
  end
end
