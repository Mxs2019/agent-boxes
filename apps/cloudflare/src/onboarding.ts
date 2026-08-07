import { ensureSystemAgent } from "./agents";
import { createCard } from "./cards";
import type { AccountRow, Card } from "./types";

interface OnboardingCardDefinition {
  title: string;
  step: string;
  html: string;
}

// The five cards reuse the marketing site's card design languages
// (apps/web/public/styles.css): swiss poster, split-flap board, terminal,
// editorial serif, and boarding pass. Shared conventions: a mono header row,
// a mono footer above a hairline rule, and the site's card palette.
const ONBOARDING_CARDS: readonly OnboardingCardDefinition[] = [
  {
    title: "Onboarding Cards · Step 1 of 5",
    step: "dismiss",
    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; }
    html, body { min-height: 100%; }
    body {
      padding: 26px 24px 22px;
      background: #e8250c;
      color: #fff4ec;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
    }
    main { min-height: calc(100vh - 48px); display: flex; flex-direction: column; }
    header {
      display: flex; justify-content: space-between;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; opacity: 0.8;
    }
    .type {
      display: grid; gap: 4px;
      margin: auto 0;
      transform: rotate(-7deg);
      font-size: clamp(64px, 22vw, 96px);
      font-weight: 800;
      letter-spacing: -0.04em;
      line-height: 0.92;
      text-transform: uppercase;
    }
    .outline { color: transparent; -webkit-text-stroke: 2.5px #fff4ec; }
    .note { max-width: 24rem; font-size: 19px; font-weight: 600; line-height: 1.35; }
    .note b { background: #fff4ec; color: #e8250c; padding: 0 6px; border-radius: 4px; font-weight: 700; }
    footer {
      margin-top: 20px; padding-top: 12px;
      border-top: 1px solid rgba(255, 244, 236, 0.35);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; opacity: 0.8;
    }
  </style>
</head>
<body>
  <main>
    <header><span>onboarding · 01 / 05</span><span>agent box</span></header>
    <p class="type" aria-label="Swipe this card"><span>swipe</span><span class="outline">this</span><span>card</span></p>
    <p class="note">Any direction works. A cleared card goes to <b>History</b>, not the trash — so swipe like you mean it.</p>
    <footer>cards are made to move</footer>
  </main>
</body>
</html>`,
  },
  {
    title: "Onboarding Cards · Step 2 of 5",
    step: "snooze",
    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; }
    html, body { min-height: 100%; }
    body {
      padding: 26px 24px 22px;
      background: #0e0e10;
      color: #f5f5f2;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
    }
    main { min-height: calc(100vh - 48px); display: flex; flex-direction: column; }
    header {
      display: flex; justify-content: space-between;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; opacity: 0.75;
    }
    .board-title {
      margin-top: 26px; padding-bottom: 12px;
      border-bottom: 1px solid rgba(245, 245, 242, 0.18);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 13px; letter-spacing: 0.12em; text-transform: uppercase;
    }
    ul { list-style: none; padding: 0; }
    li {
      display: flex; align-items: center; gap: 12px;
      padding: 15px 0;
      border-bottom: 1px solid rgba(245, 245, 242, 0.1);
    }
    .dest {
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 14px; text-transform: uppercase; letter-spacing: 0.04em;
    }
    .tiles { margin-left: auto; display: flex; gap: 3px; }
    .tiles i {
      display: grid; place-items: center;
      width: 21px; height: 30px; border-radius: 3px;
      background: linear-gradient(180deg, #26262b 0 47%, #101013 47% 53%, #1f1f24 53%);
      color: #ffb224;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-style: normal; font-size: 15px; text-transform: uppercase;
    }
    li.dim { opacity: 0.45; }
    .instruction { margin: auto 0 0; font-size: 21px; font-weight: 650; line-height: 1.3; }
    .instruction b { color: #ffb224; font-weight: 700; }
    .detail { margin-top: 10px; font-size: 15px; line-height: 1.45; opacity: 0.65; }
    footer {
      margin-top: 20px; padding-top: 12px;
      border-top: 1px solid rgba(245, 245, 242, 0.18);
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; opacity: 0.75;
    }
  </style>
</head>
<body>
  <main>
    <header><span>onboarding · 02 / 05</span><span>departures</span></header>
    <p class="board-title">Departures — your deck</p>
    <ul>
      <li>
        <span class="dest">this card</span>
        <span class="tiles" aria-label="1 week"><i>1</i><i> </i><i>w</i><i>e</i><i>e</i><i>k</i></span>
      </li>
      <li class="dim">
        <span class="dest">morning brief</span>
        <span class="tiles" aria-label="On time"><i>o</i><i>n</i><i> </i><i>t</i><i>i</i><i>m</i><i>e</i></span>
      </li>
    </ul>
    <p class="instruction">Not for now? Tap the <b>clock</b> below and choose 1 week.</p>
    <p class="detail">The card leaves your deck today and lands back on top when it is due. Nothing nags in between.</p>
    <footer>cards wait for you — not the other way</footer>
  </main>
</body>
</html>`,
  },
  {
    title: "Onboarding Cards · Step 3 of 5",
    step: "agent",
    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; }
    html, body { min-height: 100%; }
    body {
      padding: 24px 22px 20px;
      background: #10151a;
      color: #aeb9c2;
      font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, monospace;
    }
    main { min-height: calc(100vh - 44px); display: flex; flex-direction: column; }
    .chrome {
      display: flex; align-items: center; gap: 7px;
      padding-bottom: 14px; margin-bottom: 18px;
      border-bottom: 1px solid rgba(174, 185, 194, 0.16);
      font-size: 12px;
    }
    .chrome i { width: 11px; height: 11px; border-radius: 50%; background: #ff5f57; }
    .chrome i:nth-child(2) { background: #febc2e; }
    .chrome i:nth-child(3) { background: #28c840; }
    .chrome span { margin-left: auto; opacity: 0.6; }
    .line { font-size: 15px; line-height: 2; }
    .prompt { color: #31e981; }
    .strong { color: #e6edf3; }
    h1 { margin: 14px 0 6px; color: #ffffff; font-size: 27px; line-height: 1.15; letter-spacing: -0.03em; font-weight: 600; }
    ol { list-style: none; padding: 0; margin: 14px 0 0; }
    li {
      display: grid; grid-template-columns: 34px 1fr; gap: 10px;
      padding: 12px 0; border-top: 1px solid rgba(174, 185, 194, 0.14);
      font-size: 15px; line-height: 1.4;
    }
    li::before { color: #31e981; font-weight: 700; }
    li:nth-child(1)::before { content: "01"; }
    li:nth-child(2)::before { content: "02"; }
    li:nth-child(3)::before { content: "03"; }
    li b { color: #e6edf3; font-weight: 600; }
    .diff {
      margin: auto 0 0; padding: 12px 14px;
      border-left: 2px solid #31e981; border-radius: 0 8px 8px 0;
      background: #161d24;
      font-size: 13.5px; line-height: 1.8;
    }
    .del { color: #f85149; }
    .ok { color: #3fb950; }
    .cursor { display: inline-block; width: 9px; height: 17px; margin-left: 2px; vertical-align: text-bottom; background: #31e981; animation: blink 1.1s steps(1) infinite; }
    @keyframes blink { 50% { opacity: 0; } }
    footer {
      margin-top: 18px; padding-top: 12px;
      border-top: 1px solid rgba(174, 185, 194, 0.16);
      font-size: 12px; opacity: 0.7;
    }
  </style>
</head>
<body>
  <main>
    <div class="chrome"><i></i><i></i><i></i><span>onboarding · 03 / 05</span></div>
    <p class="line"><span class="prompt">❯</span> agentbox agents new<span class="cursor" aria-hidden="true"></span></p>
    <h1>Give an agent a key.</h1>
    <ol>
      <li><span>Tap the <b>key</b> at the top of the deck.</span></li>
      <li><span>Choose <b>New agent</b> and name it.</span></li>
      <li><span>Copy the instructions into your agent — Claude Code, a cron job, anything that can POST.</span></li>
    </ol>
    <div class="diff"><span class="del">- email: anyone can reach you</span><br><span class="ok">+ deck: only keys you created</span></div>
    <footer>no address to guess · no list to buy</footer>
  </main>
</body>
</html>`,
  },
  {
    title: "Onboarding Cards · Step 4 of 5",
    step: "feedback",
    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; }
    html, body { min-height: 100%; }
    body {
      padding: 26px 26px 22px;
      background: #f6f0e1;
      color: #221f18;
      font-family: "New York", Georgia, "Times New Roman", serif;
    }
    main { min-height: calc(100vh - 48px); display: flex; flex-direction: column; }
    .mast { font-size: 34px; font-weight: 600; letter-spacing: -0.01em; line-height: 1; text-align: center; }
    .dateline {
      margin-top: 12px; padding: 7px 0;
      border-top: 1px solid #221f18; border-bottom: 1px solid #221f18;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 10.5px; letter-spacing: 0.14em; text-transform: uppercase; text-align: center;
    }
    h1 { margin-top: 24px; font-size: clamp(30px, 9vw, 40px); font-weight: 500; letter-spacing: -0.015em; line-height: 1.08; }
    .lead { margin-top: 14px; font-size: 18px; line-height: 1.5; }
    .lead::first-letter { float: left; padding: 4px 8px 0 0; font-size: 52px; line-height: 0.8; font-weight: 600; }
    .lead b { font-weight: 700; }
    blockquote {
      margin: auto 0 0; padding: 16px 0 4px 18px;
      border-left: 4px solid #221f18;
      font-size: 20px; font-style: italic; line-height: 1.35;
    }
    cite {
      display: block; margin-top: 8px;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11px; font-style: normal; letter-spacing: 0.1em; text-transform: uppercase; opacity: 0.6;
    }
    footer {
      margin-top: 18px; padding-top: 10px;
      border-top: 3px double #221f18;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 11.5px; opacity: 0.75;
    }
  </style>
</head>
<body>
  <main>
    <p class="mast">The Feedback Loop</p>
    <p class="dateline">onboarding · step 4 of 5</p>
    <h1>Agents take notes. Leave one.</h1>
    <p class="lead">Tap the <b>three dots (⋯)</b> under this card, then <b>Leave Feedback</b>. Your note and a copy of the card go to the agent that sent it, to read on its next run. This card takes feedback too — it reaches the people who make Agent Box, so say anything.</p>
    <blockquote>“Shorter. Put the decision first. Lose the confetti.”<cite>— a reader, to their briefing agent</cite></blockquote>
    <footer>agents improve when you tell them how</footer>
  </main>
</body>
</html>`,
  },
  {
    title: "Onboarding Cards · Step 5 of 5",
    step: "history",
    html: `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    * { box-sizing: border-box; margin: 0; }
    html, body { min-height: 100%; }
    body {
      padding: 26px 24px 22px;
      background: #ffffff;
      color: #131410;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", sans-serif;
    }
    main { min-height: calc(100vh - 48px); display: flex; flex-direction: column; }
    header {
      display: flex; justify-content: space-between;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; color: #1c47e3;
    }
    .route {
      display: flex; align-items: baseline; gap: 10px;
      margin-top: 26px;
      font-size: clamp(38px, 12.5vw, 54px); font-weight: 750; letter-spacing: -0.035em;
    }
    .route .arrow { color: #ff4b00; font-size: 0.5em; }
    .meta {
      display: grid; grid-template-columns: 1fr 1fr; gap: 14px 16px;
      margin-top: 22px; padding: 0; list-style: none;
    }
    .meta span {
      display: block;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 10.5px; letter-spacing: 0.12em; text-transform: uppercase; color: #6d6f64;
    }
    .meta b { font-size: 17px; font-weight: 600; }
    .tear { position: relative; height: 0; margin: auto -24px 20px; border-top: 2px dashed #c9cabe; }
    .tear::before, .tear::after {
      content: ""; position: absolute; top: -9px; width: 18px; height: 18px;
      border-radius: 50%; background: #fbfbf8; border: 1px solid #e4e5da;
    }
    .tear::before { left: -9px; }
    .tear::after { right: -9px; }
    .stub { display: flex; gap: 14px; align-items: center; }
    .qr {
      flex: none; width: 64px; height: 64px; border-radius: 4px;
      background:
        repeating-linear-gradient(0deg, #131410 0 3px, transparent 3px 7px),
        repeating-linear-gradient(90deg, #131410 0 3px, #fff 3px 7px);
    }
    .stub p { font-size: 15px; line-height: 1.45; color: #4c4e44; }
    .stub b { color: #131410; font-weight: 650; }
    footer {
      margin-top: 18px; padding-top: 12px;
      border-top: 1px solid #e4e5da;
      font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
      font-size: 12px; color: #6d6f64;
    }
  </style>
</head>
<body>
  <main>
    <header><span>onboarding · 05 / 05</span><span>boarding complete</span></header>
    <p class="route"><span>DECK</span><span class="arrow">→</span><span>DONE</span></p>
    <ul class="meta">
      <li><span>kept</span><b>every card</b></li>
      <li><span>lost</span><b>nothing</b></li>
      <li><span>unread guilt</span><b>none</b></li>
      <li><span>next up</span><b>your agents</b></li>
    </ul>
    <div class="tear" aria-hidden="true"></div>
    <div class="stub">
      <div class="qr" aria-hidden="true"></div>
      <p>Everything you clear waits in <b>History</b>, at the top. Swipe this card away and the deck is yours.</p>
    </div>
    <footer>nothing here demands an instant reply</footer>
  </main>
</body>
</html>`,
  },
];

export async function resetOnboardingCards(
  db: D1Database,
  account: AccountRow,
  encryptionSecret: string,
): Promise<Card[]> {
  const agentId = await ensureSystemAgent(db, account, encryptionSecret);
  const now = Math.floor(Date.now() / 1000);
  await db
    .prepare(
      `UPDATE cards
       SET cleared_at = ?1
       WHERE account_id = ?2
         AND source = 'system'
         AND cleared_at IS NULL
         AND json_extract(metadata_json, '$.onboarding') = 1`,
    )
    .bind(now, account.id)
    .run();

  const cards: Card[] = [];
  for (const [index, definition] of ONBOARDING_CARDS.entries()) {
    const result = await createCard(db, account, {
      title: definition.title,
      html: definition.html,
      expiresIn: "never",
      source: "system",
      sourceName: "Agent Box",
      agentId,
      metadata: {
        onboarding: 1,
        onboarding_step: definition.step,
        onboarding_position: index + 1,
      },
    });
    cards.push(result.card);
  }
  return cards;
}
