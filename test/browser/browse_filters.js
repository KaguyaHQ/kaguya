// Run against a populated local Kaguya server with:
// playwright-cli run-code --filename=test/browser/browse_filters.js
async page => {
  page.setDefaultTimeout(10000)
  const base = "http://localhost:4001/browse"
  const check = (condition, message) => { if (!condition) throw new Error(message) }
  const query = () => ({get: key => {
    const pairs = (page.url().split("?")[1] || "").split("&").map(pair => pair.split("="))
    return pairs.find(([name]) => name === key)?.[1] ?? null
  }})
  const waitParam = (key, value) => page.waitForURL(url => url.searchParams.get(key) === value)
  const heading = page.getByRole("heading", {name: "Visual novels", exact: true})
  const range = async (key, value, close) => {
    await page.locator(`#browse-desktop-range-${key}-trigger`).click()
    const input = page.locator(`#browse-desktop-range-${key}-form input[name=${key}]`)
    await input.fill(value)
    if (close === "Enter") await input.press("Enter")
    else if (close === "Escape") await input.press("Escape")
    else await heading.click()
    await waitParam(key, value || null)
  }

  await page.setViewportSize({width: 1440, height: 1000})
  await page.goto(base)
  await page.locator("[data-phx-main].phx-connected").waitFor()
  // Growing an already-open disclosure must keep it anchored and on screen.
  const ratingTrigger = page.locator("#browse-desktop-range-minRating-trigger")
  const ratingPanel = page.locator("#browse-desktop-range-minRating-panel")
  check(await ratingTrigger.getAttribute("aria-controls") === "browse-desktop-range-minRating-panel", "Disclosure must identify its controlled panel")
  check(await ratingTrigger.getAttribute("aria-haspopup") !== "true", "A form disclosure must not claim ARIA menu semantics")
  const originalTriggerStyle = await ratingTrigger.getAttribute("style")
  await ratingTrigger.evaluate(el => { el.style.cssText = "position:fixed;bottom:24px;left:300px;z-index:1000" })
  await ratingTrigger.click()
  await page.waitForFunction(() => document.getElementById("browse-desktop-range-minRating-panel").dataset.side === "top")
  await ratingPanel.evaluate(el => { el.style.minHeight = "360px" })
  await page.waitForFunction(() => {
    const panel = document.getElementById("browse-desktop-range-minRating-panel").getBoundingClientRect()
    const trigger = document.getElementById("browse-desktop-range-minRating-trigger").getBoundingClientRect()
    return panel.height >= 360 && panel.top >= 8 && Math.abs(trigger.top - panel.bottom - 8) < 2
  })
  await ratingPanel.evaluate(el => { el.style.minHeight = "" })
  await ratingTrigger.evaluate((el, original) => {
    if (original === null) el.removeAttribute("style")
    else el.setAttribute("style", original)
  }, originalTriggerStyle)
  await page.keyboard.press("Escape")
  await range("minRating", "4", "outside")
  await range("minRating", "3.5", "Enter")
  check(!(await page.locator("#browse-desktop-range-minRating-panel").evaluate(e => e.matches(":popover-open"))), "Enter must close the filter")
  await range("fromYear", "2010", "Escape")
  check(query().get("minRating") === "3.5", "Year must preserve rating")
  await range("minRatings", "5", "outside")

  await page.locator("#browse-tags-popover-trigger").click()
  await page.locator("#browse-tags-popover-panel").getByRole("button", {name: /^Romance/}).click()
  await page.keyboard.press("Escape")
  await waitParam("tags", "romance")
  check(query().get("fromYear") === "2010", "Tags must preserve year")

  await page.getByRole("link", {name: "Clear Tags filter", exact: true}).click()
  await waitParam("tags", null)
  await page.locator("#browse-desktop-range-minRating-trigger").click()
  await page.locator("#browse-desktop-range-minRating-form input[name=minRating]").fill("4.5")
  await page.getByRole("link", {name: "Clear Rating filter", exact: true}).click()
  await waitParam("minRating", null)
  // Flush pending popover toggles/animation frames before checking for stale reapply.
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
  check(query().get("minRating") === null, "Clear must discard the open draft")

  await range("fromYear", "", "Enter")
  await page.locator("#browse-more-trigger").click()
  await page.waitForFunction(() => document.getElementById("browse-more-trigger").getAttribute("aria-expanded") === "true")
  await page.locator("#browse-multi-languages-trigger").waitFor({state: "visible"})
  await page.locator("#browse-more-trigger").click()
  await page.waitForFunction(() => document.getElementById("browse-more-trigger").getAttribute("aria-expanded") === "false")
  await page.locator("#browse-multi-languages-trigger").waitFor({state: "hidden"})
  await page.locator("#browse-more-trigger").click()
  await page.locator("#browse-multi-languages-trigger").waitFor({state: "visible"})
  await page.locator("#browse-multi-languages-trigger").click()
  await page.locator("#browse-multi-languages-panel").getByRole("link", {name: "English", exact: true}).click()
  await waitParam("languages", "en")
  await page.locator("#browse-more-trigger").click()
  await page.locator("#browse-multi-languages-trigger").waitFor({state: "hidden"})
  check(query().get("languages") === "en", "Collapsing More must retain selected filters")

  await page.goto(base)
  await page.setViewportSize({width: 390, height: 844})
  await page.getByRole("button", {name: "Filters", exact: true}).click()
  const mobile = page.locator("#browse-mobile-filter-form")
  await mobile.locator("input[name=minRating]").fill("3.5")
  await mobile.getByRole("button", {name: "Done", exact: true}).click()
  await waitParam("minRating", "3.5")
  await page.goto(base)
  return "Passed: disclosure semantics and resize anchoring; mobile decimal submission; range close/Enter/Escape, tag apply, combined filters, empty input clearing, clear-over-draft, More state"
}
