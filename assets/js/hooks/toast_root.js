import {wireToast} from "../lib/toast"

const ToastRoot = {
  mounted() { this._wire() },
  updated() { this._wire() },
  _wire() {
    this.el.querySelectorAll("[data-kaguya-toast]").forEach(wireToast)
  }
}

export default ToastRoot
