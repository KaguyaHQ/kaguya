const VndbImportUploader = {
  mounted() {
    this.file = null
    this.uploading = false

    this.onChange = () => {
      const file = this.input?.files?.[0]
      if (file) this.selectFile(file)
    }

    this.onSubmit = async event => {
      event.preventDefault()

      if (this.uploading || this.el.dataset.status === "importing") return

      const file = this.file || this.input?.files?.[0]
      if (!file) {
        this.pushEvent("import-file-error", {message: "Choose a file first."})
        return
      }

      this.uploading = true

      const request = await this.requestUpload(file)
      if (!request?.ok) {
        this.uploading = false
        return
      }

      try {
        const response = await fetch(request.upload_url, {
          method: "PUT",
          headers: {"Content-Type": file.type || "application/xml"},
          body: file
        })

        if (!response.ok) throw new Error(`Upload failed with status ${response.status}`)

        this.pushEvent("start-import", {upload_id: request.upload_id, name: file.name})
      } catch (error) {
        this.uploading = false
        console.warn("[VndbImportUploader] upload failed", error)
        this.pushEvent("import-file-error", {
          message: "The file could not be uploaded. Choose your VNDB XML export again."
        })
      }
    }

    this.onDragOver = event => {
      event.preventDefault()
    }

    this.onDrop = event => {
      event.preventDefault()
      const file = event.dataTransfer?.files?.[0]
      if (file) this.selectFile(file)
    }

    this.bindElements()
    this.el.addEventListener("dragover", this.onDragOver)
    this.el.addEventListener("drop", this.onDrop)
  },

  updated() {
    if (this.el.dataset.status === "not_selected") this.file = null
    if (this.el.dataset.status !== "importing") this.uploading = false
    this.bindElements()
  },

  destroyed() {
    this.input?.removeEventListener("change", this.onChange)
    this.form?.removeEventListener("submit", this.onSubmit)
    this.el.removeEventListener("dragover", this.onDragOver)
    this.el.removeEventListener("drop", this.onDrop)
  },

  bindElements() {
    const input = document.getElementById(this.el.dataset.inputId)
    if (input !== this.input) {
      this.input?.removeEventListener("change", this.onChange)
      this.input = input
      this.input?.addEventListener("change", this.onChange)
    }

    const form = this.el.closest("form")
    if (form !== this.form) {
      this.form?.removeEventListener("submit", this.onSubmit)
      this.form = form
      this.form?.addEventListener("submit", this.onSubmit)
    }
  },

  selectFile(file) {
    if (this.el.dataset.status === "importing") return

    this.file = file
    this.pushEvent("select-import-file", {name: file.name, size: file.size})
  },

  requestUpload(file) {
    return new Promise(resolve => {
      this.pushEvent("request-import-upload", {name: file.name, size: file.size}, reply => {
        if (!reply?.ok) {
          this.pushEvent("import-file-error", {
            message: reply?.error || "The file could not be uploaded. Choose your VNDB XML export again."
          })
          resolve(null)
          return
        }

        resolve(reply)
      })
    })
  }
}

export default VndbImportUploader
