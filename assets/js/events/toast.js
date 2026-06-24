import {showKaguyaToast} from "../lib/toast"

window.addEventListener("phx:toast", event => showKaguyaToast(event.detail))
window.addEventListener("kaguya:toast", event => showKaguyaToast(event.detail))
