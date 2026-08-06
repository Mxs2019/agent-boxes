const baseURL = (process.env.AGENT_BOX_BASE_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");

const response = await fetch(`${baseURL}/v1/accounts`, { method: "POST" });
if (!response.ok) {
  throw new Error(`Account creation failed with ${response.status}: ${await response.text()}`);
}

const result = await response.json();
console.log(`Account key: ${result.account_key}`);
console.log("Store this key now. Agent Box cannot show it again.");
