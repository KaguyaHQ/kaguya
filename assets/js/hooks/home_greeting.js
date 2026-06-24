// Mirror the client greeting behavior used by Next.js
// (`../personal/legacy-next-app/src/lib/getGreeting.ts`). The browser owns local time, so
// this cosmetic text is computed client-side without a LiveView roundtrip.
//
// `applyHomeGreeting()` is called directly from app.js on load, so the
// greeting fills in as soon as the deferred bundle parses — it does NOT
// wait for the websocket to connect. The hook below only re-applies it on
// client-side navigation, where live_navigate recreates the element.

const genericGreetings = [
  (u) => `Welcome back, ${u}.`,
  (u) => `${u} returns!`,
  (u) => `Ah, ${u}. Welcome back.`,
  (u) => `Good to see you, ${u}.`,
  (u) => `Hey, ${u}.`
]

function hashString(str) {
  let hash = 0
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i)
    hash = (hash << 5) - hash + char
    hash = hash & hash
  }
  return Math.abs(hash)
}

function getTimeBasedGreeting(username, hour, seed) {
  if (hour >= 0 && hour < 5) {
    const lateNight = [
      `Late night, ${username}.`,
      `Burning the midnight oil, ${username}?`,
      `Can't sleep, ${username}?`
    ]
    return lateNight[seed % lateNight.length]
  }

  if (hour >= 5 && hour < 7) {
    const earlyMorning = [
      `Early start, ${username}.`,
      `Up early, ${username}?`,
      `Rise and shine, ${username}.`
    ]
    return earlyMorning[seed % earlyMorning.length]
  }

  if (hour < 12) {
    const morning = [`Good morning, ${username}.`, `Morning, ${username}.`]
    return morning[seed % morning.length]
  }

  if (hour < 17) {
    const afternoon = [`Good afternoon, ${username}.`, `Afternoon, ${username}.`]
    return afternoon[seed % afternoon.length]
  }

  if (hour < 21) {
    const evening = [`Good evening, ${username}.`, `Evening, ${username}.`]
    return evening[seed % evening.length]
  }

  const night = [`Good night, ${username}.`, `Night, ${username}.`]
  return night[seed % night.length]
}

function greetingFor(displayName) {
  const now = new Date()
  const hour = now.getHours()
  const threeHourBlock = Math.floor(hour / 3)
  const hourKey = `${now.toDateString()}-${threeHourBlock}`
  const seed = hashString(displayName + hourKey)
  const useTimeBased = seed % 100 < 75

  return useTimeBased
    ? getTimeBasedGreeting(displayName, hour, seed)
    : genericGreetings[seed % genericGreetings.length](displayName)
}

// Fill the greeting heading from local time. Safe to call repeatedly — it
// no-ops when the text already matches, so the app.js load pass and the
// hook re-apply never cause a flash.
export function applyHomeGreeting(header = document.getElementById("home-greeting")) {
  if (!header) return

  const displayName = header.dataset.displayName
  if (!displayName) return

  const heading = header.querySelector("[data-home-greeting-text]")
  if (!heading) return

  const greeting = greetingFor(displayName)
  if (heading.textContent === greeting) return

  heading.textContent = greeting
}

const HomeGreeting = {
  mounted() {
    applyHomeGreeting(this.el)
  },

  updated() {
    applyHomeGreeting(this.el)
  }
}

export default HomeGreeting
