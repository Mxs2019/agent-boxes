// ---------- copy buttons ----------

async function copyText(value, button) {
  await navigator.clipboard.writeText(value);
  const previous = button.textContent;
  button.textContent = "Copied";
  window.setTimeout(() => {
    button.textContent = previous;
  }, 1400);
}

document.addEventListener("click", async (event) => {
  const button = event.target.closest("[data-copy-target]");
  if (!(button instanceof HTMLButtonElement)) return;
  const target = document.getElementById(button.dataset.copyTarget ?? "");
  if (!target) return;
  try {
    await copyText(target.textContent ?? "", button);
  } catch {
    button.textContent = "Copy failed";
  }
});

// ---------- account creation ----------

const createButton = document.getElementById("create-account");
const status = document.getElementById("account-status");
const result = document.getElementById("account-result");
const key = document.getElementById("account-key");

createButton?.addEventListener("click", async () => {
  if (!(createButton instanceof HTMLButtonElement)) return;
  createButton.disabled = true;
  if (status) status.textContent = "Creating your account…";
  try {
    const response = await fetch("/v1/accounts", { method: "POST" });
    const payload = await response.json();
    if (!response.ok) {
      throw new Error(payload?.error?.message ?? "The account request failed.");
    }
    if (key) key.textContent = payload.account_key;
    if (result) result.hidden = false;
    if (status) status.textContent = "Your account is ready. Save the key now.";
    createButton.hidden = true;
    result?.scrollIntoView({ behavior: "smooth", block: "nearest" });
  } catch (error) {
    if (status) {
      status.textContent = error instanceof Error ? error.message : "The account request failed.";
    }
    createButton.disabled = false;
  }
});

// ---------- hero carousel ----------

const carousel = document.getElementById("carousel");

document.addEventListener("click", (event) => {
  const button = event.target.closest("[data-carousel]");
  if (!(button instanceof HTMLButtonElement) || !carousel) return;
  const direction = Number(button.dataset.carousel) || 1;
  const card = carousel.querySelector(".ex-card");
  const step = card ? card.getBoundingClientRect().width + 16 : 300;
  carousel.scrollBy({ left: direction * step, behavior: "smooth" });
});

// ---------- deck demo ----------

const deck = document.getElementById("deck");
const deckCount = document.getElementById("deck-count");
const deckEmpty = document.getElementById("deck-empty");
const deckReset = document.getElementById("deck-reset");
const deckTotal = deck ? deck.children.length : 0;
const deckInitialHtml = deck ? deck.innerHTML : "";
let cleared = 0;

function activeCards() {
  return deck ? [...deck.querySelectorAll(".deck-card:not(.leaving)")] : [];
}

function layoutDeck() {
  const cards = activeCards();
  cards.forEach((card, index) => {
    const depth = cards.length - 1 - index;
    card.style.setProperty("--depth", String(Math.min(depth, 3)));
    card.classList.toggle("buried", depth > 2);
  });
  if (deckCount) {
    deckCount.textContent = `${Math.min(cleared + 1, deckTotal)} / ${deckTotal}`;
  }
  if (deckEmpty) deckEmpty.hidden = cards.length > 0;
  if (deckCount && cards.length === 0) deckCount.textContent = `${deckTotal} / ${deckTotal}`;
}

const reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");

// Toss the card out with its release momentum. Position and rotation
// integrate per frame from the flick velocity (px/ms and deg/ms).
function dismissCard(card, offsetX, offsetY, velocityX, velocityY) {
  card.classList.add("leaving");
  card.classList.remove("dragging");
  cleared += 1;
  layoutDeck();

  if (reducedMotion.matches) {
    card.remove();
    layoutDeck();
    return;
  }

  let speed = Math.hypot(velocityX, velocityY);
  if (speed < 0.1) {
    // No usable flick reading: leave along the drag displacement instead.
    const magnitude = Math.hypot(offsetX, offsetY) || 1;
    velocityX = offsetX / magnitude;
    velocityY = offsetY / magnitude;
    speed = 1;
  }
  // Keep slow releases brisk and violent flicks sane.
  const scale = Math.min(Math.max(speed, 1.5), 3.6) / speed;
  velocityX *= scale;
  velocityY *= scale;

  let x = offsetX;
  let y = offsetY;
  let rotation = offsetX * 0.06;
  const spin = velocityX * 9;
  let last = performance.now();
  const step = (now) => {
    const dt = Math.min(now - last, 32);
    last = now;
    x += velocityX * dt;
    y += velocityY * dt;
    rotation += (spin * dt) / 1000;
    card.style.transform = `translate(${x}px, ${y}px) rotate(${rotation}deg)`;
    if (Math.hypot(x, y) < 900 && card.isConnected) {
      requestAnimationFrame(step);
    } else {
      card.remove();
      layoutDeck();
    }
  };
  requestAnimationFrame(step);
}

if (deck) {
  let pointerId = null;
  let startX = 0;
  let startY = 0;
  let dragging = false;
  let dragCard = null;
  let trail = [];

  deck.addEventListener("pointerdown", (event) => {
    const cards = activeCards();
    const top = cards[cards.length - 1];
    if (!top || !top.contains(event.target)) return;
    pointerId = event.pointerId;
    startX = event.clientX;
    startY = event.clientY;
    dragCard = top;
    dragging = false;
    trail = [{ x: event.clientX, y: event.clientY, t: performance.now() }];
  });

  const resetDrag = () => {
    if (dragCard && dragging) {
      dragCard.classList.remove("dragging");
      dragCard.style.transform = "";
    }
    pointerId = null;
    dragCard = null;
    dragging = false;
    trail = [];
  };

  // Release velocity in px/ms, read from the last ~90 ms of pointer travel.
  function flickVelocity() {
    const now = performance.now();
    const recent = trail.filter((point) => now - point.t <= 90);
    const from = recent[0] ?? trail[trail.length - 1];
    const to = trail[trail.length - 1];
    if (!from || !to || to.t - from.t < 8) return { vx: 0, vy: 0 };
    const dt = to.t - from.t;
    return { vx: (to.x - from.x) / dt, vy: (to.y - from.y) / dt };
  }

  deck.addEventListener("pointermove", (event) => {
    if (event.pointerId !== pointerId || !dragCard) return;
    // A hover move with no button held means the release happened elsewhere.
    if (event.pointerType === "mouse" && (event.buttons & 1) === 0) {
      resetDrag();
      return;
    }
    const dx = event.clientX - startX;
    const dy = event.clientY - startY;
    trail.push({ x: event.clientX, y: event.clientY, t: performance.now() });
    if (trail.length > 12) trail.shift();
    if (!dragging && Math.hypot(dx, dy) > 10) {
      dragging = true;
      dragCard.classList.add("dragging");
      dragCard.setPointerCapture?.(pointerId);
    }
    if (dragging) {
      dragCard.style.transform = `translate(${dx}px, ${dy}px) rotate(${dx * 0.06}deg)`;
    }
  });

  const release = (event) => {
    if (event.pointerId !== pointerId || !dragCard) return;
    const dx = event.clientX - startX;
    const dy = event.clientY - startY;
    const { vx, vy } = flickVelocity();
    const flicked = Math.hypot(vx, vy) > 0.55;
    if (dragging && (flicked || Math.hypot(dx, dy) > 90)) {
      dismissCard(dragCard, dx, dy, vx, vy);
      pointerId = null;
      dragCard = null;
      dragging = false;
      trail = [];
      return;
    }
    resetDrag();
  };

  window.addEventListener("pointerup", release);
  window.addEventListener("pointercancel", release);

  // Block accidental taps at the end of a drag.
  deck.addEventListener(
    "click",
    (event) => {
      if (dragging) {
        event.stopPropagation();
        event.preventDefault();
      }
    },
    true,
  );

  layoutDeck();
}

deckReset?.addEventListener("click", () => {
  if (!deck) return;
  deck.innerHTML = deckInitialHtml;
  cleared = 0;
  layoutDeck();
});

// ---------- deck mini apps (delegated, so a deck reset keeps them alive) ----------

// Slack card: tap a thread to mark it read.
document.addEventListener("click", (event) => {
  const button = event.target.closest("#slack-list button");
  if (!button) return;
  button.closest("li")?.classList.toggle("read");
  const card = button.closest(".deck-card");
  const unread = card?.querySelectorAll("#slack-list li:not(.read)").length ?? 0;
  const heading = card?.querySelector("h3");
  if (heading) {
    heading.textContent =
      unread === 0 ? "All caught up." : `${unread} unread thread${unread === 1 ? "" : "s"}.`;
  }
});

// Weather card: switch between °F and °C.
document.addEventListener("click", (event) => {
  const toggle = event.target.closest("#unit-toggle");
  if (!toggle) return;
  const card = toggle.closest(".deck-card");
  const value = card?.querySelector("#temp-value");
  const unit = card?.querySelector("#temp-unit");
  if (!value || !unit) return;
  const showCelsius = unit.textContent === "F";
  for (const el of card.querySelectorAll("[data-f]")) {
    const fahrenheit = Number(el.dataset.f ?? "72");
    const shown = showCelsius ? Math.round(((fahrenheit - 32) * 5) / 9) : fahrenheit;
    el.textContent = el === value ? String(shown) : `${shown}°`;
  }
  unit.textContent = showCelsius ? "C" : "F";
  toggle.textContent = showCelsius ? "show °F" : "show °C";
});
