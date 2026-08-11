defmodule Kaguya.Uploads.ImageVariantWorker do
  @moduledoc """
  Generates image variants from a staged upload, off the request path.

  Two execution patterns:

    * VN/character types — the DB row already exists with `id == upload_id`;
      this worker just generates variants and (for VN types) purges the
      VN's CDN cache so the new image becomes visible to public consumers.

    * avatar/banner — the swap (`user.avatar_id ← upload_id`) is performed
      by this worker after variant generation succeeds. This preserves the
      atomic-swap invariant: `user.avatar_id` only flips once variants are
      confirmed on S3, so no consumer ever sees a 404.

  Idempotent: re-running with the same args overwrites the same S3 keys
  and (for avatar/banner) is safe because `swap_user_image` is itself
  transactional. Temp files are deleted on success only — failures leave
  the temp file in place so retries can re-fetch it.
  """

  use Oban.Worker,
    queue: :images,
    max_attempts: 5,
    unique: [keys: [:type, :id], period: 3600]

  alias Kaguya.Uploads.ImageVariantProcessor

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args
    |> ImageVariantProcessor.process()
    |> handle_result(args)
  end

  @doc false
  def handle_result(result, args) do
    case result do
      :ok ->
        :ok

      {:error, {kind, reason}} when kind in [:invalid_image, :invalid_args] ->
        Logger.warning("Image variant job cancelled: #{reason}",
          error_kind: kind,
          image_type: args["type"],
          image_id: args["id"]
        )

        {:cancel, reason}

      {:error, _reason} = error ->
        error
    end
  end
end
