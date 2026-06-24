// Share interaction: the native share sheet is only useful on phones/tablets,
// so desktop browsers (which now also expose navigator.share in Chromium)
// always copy the link instead.
export const isMobileOrTabletUA = () =>
  typeof navigator !== "undefined" &&
  /(android|iphone|ipad|mobile)/i.test(navigator.userAgent || "")
