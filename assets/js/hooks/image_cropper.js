import Cropper from "cropperjs"

// Mirrors ../personal/legacy-next-app/src/components/shared/ImageCropper.tsx dimensions so
// the cropped output matches the production avatar/banner pipeline.
const VARIANT_PRESETS = {
  profile: {
    aspectRatio: 1,
    cropShape: "round",
    output: {width: 512, height: 512},
    cropBox: {mobile: 246, desktop: 211},
    container: {mobile: {w: 350, h: 350}, desktop: {w: 299, h: 299}}
  },
  cover: {
    // 1280×254 — matches backend banner variants (see images.ex)
    aspectRatio: 1280 / 254,
    cropShape: "rect",
    output: {width: 1280, height: 254},
    cropBox: {mobile: 350, desktop: 574},
    container: {mobile: {w: 350, h: 183}, desktop: {w: 574, h: 300}}
  }
}

const MOBILE_BREAKPOINT = 768

const isMobile = () => window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`).matches

const ImageCropper = {
  mounted() {
    this.variant = this.el.dataset.variant || "profile"
    this.imageType = this.el.dataset.imageType
    this.preset = VARIANT_PRESETS[this.variant] || VARIANT_PRESETS.profile

    this.fileInput = this.el.querySelector("[data-part='file-input']")
    this.image = this.el.querySelector("[data-part='cropper-image']")
    this.zoomSlider = this.el.querySelector("[data-part='zoom-slider']")
    this.zoomMinus = this.el.querySelector("[data-part='zoom-minus']")
    this.zoomPlus = this.el.querySelector("[data-part='zoom-plus']")
    this.applyBtn = this.el.querySelector("[data-part='apply']")
    this.replaceBtn = this.el.querySelector("[data-part='replace']")
    this.cancelBtn = this.el.querySelector("[data-part='cancel']")
    this.trigger = this.el.querySelector("[data-part='trigger']")
    this.modal = this.el.querySelector("[data-part='modal']")
    this.errorEl = this.el.querySelector("[data-part='error']")

    this.cropper = null
    this.cropperReady = false
    this.objectUrl = null
    this.uploading = false

    this.onTrigger = event => {
      // Sibling controls inside the trigger (e.g. "Delete Banner") opt out
      // by marking themselves with [data-cropper-skip].
      if (event?.target?.closest?.("[data-cropper-skip]")) return
      this.openPicker()
    }
    this.onFileChange = e => {
      const file = e.target.files?.[0]
      if (file) this.loadFile(file)
    }
    this.onReplace = () => this.openPicker()
    this.onCancel = () => this.closeModal()
    this.onApply = () => this.apply()
    this.onZoomInput = e => this.zoomTo(parseFloat(e.target.value))
    this.onZoomMinus = () => this.zoomBy(-0.1)
    this.onZoomPlus = () => this.zoomBy(0.1)
    this.onBackdrop = e => {
      if (e.target === this.modal) this.closeModal()
    }
    this.onKeydown = e => {
      if (e.key === "Escape" && this.el.dataset.state === "open") this.closeModal()
    }

    this.onWindowOpen = e => {
      if (e.detail?.id === this.el.id) this.openPicker()
    }

    this.trigger?.addEventListener("click", this.onTrigger)
    window.addEventListener("kaguya:open-image-cropper", this.onWindowOpen)
    this.fileInput?.addEventListener("change", this.onFileChange)
    this.replaceBtn?.addEventListener("click", this.onReplace)
    this.cancelBtn?.addEventListener("click", this.onCancel)
    this.applyBtn?.addEventListener("click", this.onApply)
    this.zoomSlider?.addEventListener("input", this.onZoomInput)
    this.zoomMinus?.addEventListener("click", this.onZoomMinus)
    this.zoomPlus?.addEventListener("click", this.onZoomPlus)
    this.modal?.addEventListener("click", this.onBackdrop)
    document.addEventListener("keydown", this.onKeydown)

    this.setZoomControlsEnabled(false)
  },

  destroyed() {
    this.teardownCropper()
    this.trigger?.removeEventListener("click", this.onTrigger)
    this.fileInput?.removeEventListener("change", this.onFileChange)
    this.replaceBtn?.removeEventListener("click", this.onReplace)
    this.cancelBtn?.removeEventListener("click", this.onCancel)
    this.applyBtn?.removeEventListener("click", this.onApply)
    this.zoomSlider?.removeEventListener("input", this.onZoomInput)
    this.zoomMinus?.removeEventListener("click", this.onZoomMinus)
    this.zoomPlus?.removeEventListener("click", this.onZoomPlus)
    this.modal?.removeEventListener("click", this.onBackdrop)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("kaguya:open-image-cropper", this.onWindowOpen)
  },

  openPicker() {
    if (this.uploading) return
    this.fileInput.value = ""
    this.fileInput.click()
  },

  loadFile(file) {
    if (!file.type.startsWith("image/")) {
      this.showError("Choose an image file.")
      return
    }
    if (file.size > 10 * 1024 * 1024) {
      this.showError("Image is larger than 10 MB.")
      return
    }
    this.showError(null)
    this.revokeObjectUrl()
    this.objectUrl = URL.createObjectURL(file)
    this.image.src = this.objectUrl
    this.openModal()
    this.initCropper()
  },

  initCropper() {
    this.teardownCropper()
    this.setZoomControlsEnabled(false)

    const mobile = isMobile()
    const cropBoxSize = mobile ? this.preset.cropBox.mobile : this.preset.cropBox.desktop
    const cropBoxWidth = this.preset.cropShape === "rect"
      ? cropBoxSize
      : cropBoxSize
    const cropBoxHeight = this.preset.cropShape === "rect"
      ? cropBoxSize / this.preset.aspectRatio
      : cropBoxSize

    let cropper

    cropper = new Cropper(this.image, {
      aspectRatio: this.preset.aspectRatio,
      viewMode: 1,
      dragMode: "move",
      autoCropArea: 1,
      restore: false,
      guides: false,
      center: false,
      highlight: false,
      cropBoxMovable: false,
      cropBoxResizable: false,
      toggleDragModeOnDblclick: false,
      background: false,
      ready: () => {
        if (this.cropper !== cropper) return

        const containerData = cropper.getContainerData()
        const cropBoxData = {
          left: (containerData.width - cropBoxWidth) / 2,
          top: (containerData.height - cropBoxHeight) / 2,
          width: cropBoxWidth,
          height: cropBoxHeight
        }
        cropper.setCropBoxData(cropBoxData)

        // Min-zoom: image must always cover the crop box (mirrors prod's
        // react-easy-crop onMediaLoaded behavior).
        const imageData = cropper.getImageData()
        const minRatio = Math.max(
          cropBoxData.width / imageData.naturalWidth,
          cropBoxData.height / imageData.naturalHeight
        )
        this.minZoom = minRatio
        this.maxZoom = minRatio * 5
        this.cropperReady = true
        cropper.zoomTo(minRatio)

        if (this.zoomSlider) {
          this.zoomSlider.min = this.minZoom
          this.zoomSlider.max = this.maxZoom
          this.zoomSlider.step = (this.maxZoom - this.minZoom) / 100
          this.zoomSlider.value = this.minZoom
        }
        this.setZoomControlsEnabled(true)

        if (this.preset.cropShape === "round") {
          this.el.querySelector(".cropper-view-box")?.classList.add("rounded-full")
          this.el.querySelector(".cropper-face")?.classList.add("rounded-full")
        }
      },
      zoom: e => {
        if (!this.canZoom()) return

        // Clamp to [minZoom, maxZoom] and sync slider.
        if (e.detail.ratio < this.minZoom) {
          e.preventDefault()
          this.cropper.zoomTo(this.minZoom)
          if (this.zoomSlider) this.zoomSlider.value = this.minZoom
        } else if (e.detail.ratio > this.maxZoom) {
          e.preventDefault()
          this.cropper.zoomTo(this.maxZoom)
          if (this.zoomSlider) this.zoomSlider.value = this.maxZoom
        } else if (this.zoomSlider) {
          this.zoomSlider.value = e.detail.ratio
        }
      }
    })
    this.cropper = cropper
  },

  teardownCropper() {
    this.cropperReady = false
    this.setZoomControlsEnabled(false)

    if (this.cropper) {
      this.cropper.destroy()
      this.cropper = null
    }
  },

  canZoom() {
    return Boolean(
      this.cropper &&
      this.cropperReady &&
      Number.isFinite(this.minZoom) &&
      Number.isFinite(this.maxZoom)
    )
  },

  zoomTo(value) {
    if (!this.canZoom() || !Number.isFinite(value)) return

    const ratio = Math.min(this.maxZoom, Math.max(this.minZoom, value))
    this.cropper.zoomTo(ratio)
  },

  zoomBy(value) {
    if (!this.canZoom()) return
    this.cropper.zoom(value)
  },

  setZoomControlsEnabled(enabled) {
    if (this.zoomSlider) this.zoomSlider.disabled = !enabled
    if (this.zoomMinus) this.zoomMinus.disabled = !enabled
    if (this.zoomPlus) this.zoomPlus.disabled = !enabled
  },

  openModal() {
    this.el.dataset.state = "open"
    document.body.style.overflow = "hidden"
  },

  closeModal() {
    if (this.uploading) return
    this.el.dataset.state = "closed"
    document.body.style.overflow = ""
    this.teardownCropper()
    this.revokeObjectUrl()
  },

  revokeObjectUrl() {
    if (this.objectUrl) {
      URL.revokeObjectURL(this.objectUrl)
      this.objectUrl = null
    }
  },

  apply() {
    if (!this.cropper || !this.cropperReady || this.uploading) return
    this.uploading = true

    const canvas = this.cropper.getCroppedCanvas({
      width: this.preset.output.width,
      height: this.preset.output.height,
      imageSmoothingEnabled: true,
      imageSmoothingQuality: "high"
    })

    canvas.toBlob(
      blob => {
        if (!blob) {
          this.failApply("Could not process the image.")
          return
        }
        const previewUrl = URL.createObjectURL(blob)
        this.pushEvent("image-cropped", {image_type: this.imageType})
        this.uploadCroppedImage(blob, previewUrl)
      },
      "image/jpeg",
      0.9
    )
  },

  applyPreviewToTargets(previewUrl) {
    const previewTargets = [
      ...(this.trigger?.querySelectorAll("[data-part='preview']") || []),
      ...document.querySelectorAll(`[data-cropper-preview="${this.imageType}"]`)
    ]
    previewTargets.forEach(img => {
      if (img.tagName !== "IMG") return
      if (img.dataset.objectUrl) URL.revokeObjectURL(img.dataset.objectUrl)
      img.src = previewUrl
      img.dataset.objectUrl = previewUrl
      // Drop the srcset so the browser uses the new src instead of resolving
      // back to the old responsive URL.
      img.removeAttribute("srcset")
    })
  },

  uploadCroppedImage(blob, previewUrl) {
    this.pushEvent("request-image-upload", {image_type: this.imageType}, reply => {
      if (!reply?.upload_url || !reply?.upload_id) {
        if (previewUrl) URL.revokeObjectURL(previewUrl)
        this.failApply(reply?.error || "Could not get an upload URL.")
        return
      }

      fetch(reply.upload_url, {
        method: "PUT",
        headers: {"Content-Type": "image/jpeg"},
        body: blob
      })
        .then(response => {
          if (!response.ok) {
            return response.text().then(body => {
              const detail = body ? `: ${body.slice(0, 200)}` : ""
              throw new Error(`Upload failed with status ${response.status}${detail}`)
            })
          }
          this.applyPreviewToTargets(previewUrl)
          this.uploading = false
          this.closeModal()
          this.pushEvent("image-uploaded", {
            upload_id: reply.upload_id,
            image_type: this.imageType
          })
        })
        .catch(error => {
          console.warn("[ImageCropper] upload failed", error)
          if (previewUrl) URL.revokeObjectURL(previewUrl)
          this.failApply(error instanceof Error ? error.message : "Upload failed. Try again.")
        })
    })
  },

  failApply(message) {
    this.uploading = false
    this.showError(message)
    this.pushEvent("image-upload-failed", {image_type: this.imageType, message})
    // Best-effort surface — also flash via Phoenix once user is back to the
    // surface that owns the cropper.
    window.dispatchEvent(
      new CustomEvent("kaguya:image-cropper:error", {detail: {message, image_type: this.imageType}})
    )
  },

  showError(message) {
    if (!this.errorEl) return
    if (message) {
      this.errorEl.textContent = message
      this.errorEl.hidden = false
    } else {
      this.errorEl.textContent = ""
      this.errorEl.hidden = true
    }
  }
}

export default ImageCropper
