const baseURL = (process.env.AGENT_BOX_BASE_URL ?? "http://127.0.0.1:8787").replace(/\/$/, "");
const accountKey = process.env.AGENT_BOX_ACCOUNT_KEY;
const name = process.argv.slice(2).join(" ").trim();

if (!name || !accountKey) {
  console.error(
    "Usage: AGENT_BOX_ACCOUNT_KEY='YOUR_ACCOUNT_KEY' npm run agent:create -- <agent name>",
  );
  process.exit(1);
}

const response = await fetch(`${baseURL}/v1/agents`, {
  method: "POST",
  headers: {
    authorization: `Bearer ${accountKey}`,
    "content-type": "application/json",
  },
  body: JSON.stringify({ name }),
});

if (!response.ok) {
  throw new Error(`Agent creation failed with ${response.status}: ${await response.text()}`);
}

const result = await response.json();
console.log(`Agent: ${result.agent.name}`);
console.log(`Agent ID: ${result.agent.id}`);
console.log(`Agent key: ${result.agent_key}`);
console.log(`MCP URL: ${result.mcp_url}`);
console.log("MCP transport: Streamable HTTP");
console.log("You can view or replace this key later with the account key.");
