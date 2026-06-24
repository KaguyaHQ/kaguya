window.addEventListener("phx:kaguya:download-file", ({detail}) => {
  if (!detail?.url) return

  const anchor = document.createElement("a")
  anchor.href = detail.url
  anchor.rel = "noopener noreferrer"
  document.body.appendChild(anchor)
  anchor.click()
  anchor.remove()
})
