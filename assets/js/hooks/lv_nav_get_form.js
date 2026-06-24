import {lvNavigate} from "../lib/lv_navigate"

// Intercept a GET `<form>` submit and route it through LiveView client-side
// navigation instead of a full browser reload. The destination is
// `action?<form-query-string>`.
//
// Usage:
//   <form action="/search" method="get" phx-hook="LvNavGetForm" id="...">
// Optional `data-nav-kind="redirect"` to force a full live_redirect when
// the destination is a different LiveView module; defaults to `patch`,
// which is correct when the form stays in the same LiveView.
const LvNavGetForm = {
  mounted() {
    this._onSubmit = event => {
      event.preventDefault()
      const params = new URLSearchParams()
      for (const [key, value] of new FormData(this.el).entries()) {
        const text = String(value || "").trim()
        if (text !== "") params.append(key, text)
      }
      const query = params.toString()
      const action = this.el.getAttribute("action") || window.location.pathname
      const kind = this.el.dataset.navKind === "redirect" ? "redirect" : "patch"
      lvNavigate(query ? `${action}?${query}` : action, kind)
    }
    this.el.addEventListener("submit", this._onSubmit)
  },

  destroyed() {
    this.el.removeEventListener("submit", this._onSubmit)
  },
}

export default LvNavGetForm
