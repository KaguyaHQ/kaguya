window.addEventListener("phx:kaguya:submit-form", ({detail}) => {
  if (!detail?.selector) return

  const form = document.querySelector(detail.selector)
  if (!form) return

  if (typeof form.requestSubmit === "function") form.requestSubmit()
  else form.submit()
})
