import {createDialogController} from '../lib/dialog_controller'

const Dialog = {
  mounted() {
    this.dialog = createDialogController(this.el, () => {
      const command = this.el.getAttribute('data-on-close')
      if (command) this.liveSocket.execJS(this.el, command)
    })
    this.onOpen = event => {
      if (event.target === this.el) this.dialog.open()
    }
    this.onClose = event => {
      if (event.target === this.el) this.dialog.close()
    }
    this.el.addEventListener('kaguya:dialog-open', this.onOpen)
    this.el.addEventListener('kaguya:dialog-close', this.onClose)
    if (this.el.dataset.autoOpen !== 'false') this.dialog.open()
  },
  destroyed() {
    this.el.removeEventListener('kaguya:dialog-open', this.onOpen)
    this.el.removeEventListener('kaguya:dialog-close', this.onClose)
    this.dialog.destroy()
  }
}

export default Dialog
