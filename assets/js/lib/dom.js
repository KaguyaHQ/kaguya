export const parseJSONAttribute = (el, name, fallback = null) => {
  const value = el.dataset[name]
  if (!value) return fallback

  try {
    return JSON.parse(value)
  } catch (error) {
    console.warn(`[${name}] could not be parsed as JSON`, error)
    return fallback
  }
}

export const browserImport = src => {
  const importer = new Function("src", "return import(src)")
  return importer(src)
}

export const booleanValue = value =>
  value === true || value === "true" || value === 1 || value === "1"
