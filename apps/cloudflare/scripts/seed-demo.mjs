const baseURL = (process.env.AGENT_BOX_SEED_BASE_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const accountKey = process.env.AGENT_BOX_SEED_ACCOUNT_KEY;
const agentKey = process.env.AGENT_BOX_SEED_AGENT_KEY;

if (!agentKey) {
  console.error("Set AGENT_BOX_SEED_AGENT_KEY to an agent key before you seed cards.");
  process.exit(1);
}

const cards = [
  {
    key: "demo-market-v1",
    title: "Morning market update",
    expires_in: "24h",
    html: `
      <style>
        .gain { color: #16803c; font-weight: 700; }
        .callout { background-color: #eef5ff; border-radius: 10px; padding: 12px; }
      </style>
      <h2>Markets opened higher</h2>
      <p>Rail and semiconductor stocks led the morning move.</p>
      <div class="callout"><strong>Watch:</strong> Treasury yields after the 10:00 AM release.</div>
      <h3>Quick view</h3>
      <table>
        <thead><tr><th>Index</th><th>Move</th></tr></thead>
        <tbody>
          <tr><td>S&amp;P 500</td><td class="gain">+0.7%</td></tr>
          <tr><td>Nasdaq</td><td class="gain">+1.1%</td></tr>
        </tbody>
      </table>
    `,
  },
  {
    key: "demo-review-v1",
    title: "Things to review",
    expires_in: "72h",
    html: `
      <h2>Today</h2>
      <ol>
        <li>Review the new onboarding flow.</li>
        <li>Approve the launch copy.</li>
        <li>Check the TestFlight notes.</li>
      </ol>
      <blockquote>Focus on changes that remove work for the user.</blockquote>
    `,
  },
  {
    key: "demo-code-v1",
    title: "SQLite query to keep",
    expires_in: "7d",
    html: `
      <h2>Active deck query</h2>
      <p>This keeps cleared and expired cards out of the swipe deck.</p>
      <pre><code>SELECT * FROM cards
WHERE cleared_at IS NULL
  AND (expires_at IS NULL OR expires_at &gt; ?)
ORDER BY sequence ASC;</code></pre>
    `,
  },
  {
    key: "demo-dinner-v1",
    title: "Quick dinner plan",
    expires_in: "12h",
    html: `
      <h2>Lemon pasta</h2>
      <ul>
        <li>Spaghetti</li>
        <li>Two lemons</li>
        <li>Parmesan</li>
        <li>Black pepper</li>
      </ul>
      <p>Start the water at 6:15 PM. Dinner should take about 20 minutes.</p>
    `,
  },
  {
    key: "demo-reading-v1",
    title: "Commute reading list",
    expires_in: "48h",
    html: `
      <h2>Saved for the train</h2>
      <p>A short product strategy memo and two design notes.</p>
      <hr>
      <p><strong>Theme:</strong> Designing software that asks less from the user.</p>
    `,
  },
  {
    key: "demo-permanent-v1",
    title: "Agent Box keyboard shortcuts",
    expires_in: "never",
    html: `
      <h2>Reference card</h2>
      <p>This card does not expire. It is useful for testing long-lived content.</p>
      <table>
        <tbody>
          <tr><th>Refresh</th><td>Pull down</td></tr>
          <tr><th>Clear</th><td>Swipe left or right</td></tr>
          <tr><th>Find</th><td>Use local Search</td></tr>
        </tbody>
      </table>
    `,
  },
];

const created = [];
for (const card of cards) {
  const { key, ...payload } = card;
  const response = await fetch(`${baseURL}/v1/cards`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${agentKey}`,
      "content-type": "application/json",
      "idempotency-key": key,
    },
    body: JSON.stringify(payload),
  });
  if (!response.ok) {
    throw new Error(`Card ${key} failed with ${response.status}: ${await response.text()}`);
  }
  created.push(await response.json());
}

const cleared = [];
if (accountKey) {
  for (const card of created.slice(-2)) {
    const response = await fetch(`${baseURL}/v1/cards/${card.id}/clear`, {
      method: "POST",
      headers: { authorization: `Bearer ${accountKey}` },
    });
    if (!response.ok) {
      throw new Error(`Clear ${card.id} failed with ${response.status}: ${await response.text()}`);
    }
    cleared.push(card.id);
  }
}

console.log(`Created or reused ${created.length} demo cards.`);
console.log(
  accountKey
    ? `Cleared ${cleared.length} cards for History.`
    : "No cards were cleared because no account key was set.",
);
