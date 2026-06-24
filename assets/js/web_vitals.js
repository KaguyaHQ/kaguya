// Browser Web Vitals reporter — mirrors the Next.js
// `createWebVitalsComponent` setup. Observes Core Web Vitals (CLS, INP,
// LCP, FCP, TTFB) and POSTs them to `/api/axiom`, which the Phoenix
// controller forwards to the structured log pipeline.
//
// Drops "good" ratings client-side so we don't burn Axiom quota on
// healthy page loads. Mirrors the `beforeSendTransaction` filter in
// `../personal/legacy-next-app/src/instrumentation-client.ts`.

import {onCLS, onFCP, onINP, onLCP, onTTFB} from "web-vitals"

const ENDPOINT = "/api/axiom"

const csrfToken =
  document.querySelector("meta[name='csrf-token']")?.content || null

const post = body => {
  const payload = JSON.stringify(body)
  // sendBeacon is fire-and-forget and survives page unload — important for
  // CLS/LCP, which often arrive right as the user navigates away.
  if (navigator.sendBeacon) {
    const blob = new Blob([payload], {type: "application/json"})
    navigator.sendBeacon(ENDPOINT, blob)
    return
  }
  fetch(ENDPOINT, {
    method: "POST",
    keepalive: true,
    headers: {
      "content-type": "application/json",
      "x-csrf-token": csrfToken || "",
    },
    body: payload,
  }).catch(() => {})
}

const report = metric => {
  // Only ship "needs-improvement" and "poor" ratings — good vitals are not
  // actionable and would bury the bad ones in dashboards.
  if (metric.rating === "good") return

  post({
    event_type: "WEB_VITAL",
    name: metric.name,
    value: Math.round(metric.value),
    rating: metric.rating,
    page: location.pathname,
    delta: Math.round(metric.delta),
    id: metric.id,
  })
}

onCLS(report)
onFCP(report)
onINP(report)
onLCP(report)
onTTFB(report)
