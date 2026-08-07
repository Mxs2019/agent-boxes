import { HttpError } from "./errors";
import { readLimitedBody } from "./http";

export const MCP_PROTOCOL_VERSION = "2025-11-25";

const SUPPORTED_PROTOCOL_VERSIONS = new Set([MCP_PROTOCOL_VERSION, "2025-06-18", "2025-03-26"]);
const MAX_MCP_MESSAGE_BYTES = 512 * 1024;

type JsonRpcId = string | number;

interface JsonRpcRequest {
  jsonrpc: "2.0";
  id?: JsonRpcId;
  method: string;
  params?: Record<string, unknown>;
}

export interface McpToolResult {
  structuredContent: Record<string, unknown>;
  text?: string;
}

interface McpOptions {
  authenticate(): Promise<void>;
  instructions: string;
  invokeTool(name: string, argumentsValue: Record<string, unknown>): Promise<McpToolResult>;
}

const CARD_RESULT_SCHEMA = {
  type: "object",
  properties: {
    id: { type: "string", description: "The new or existing card ID." },
    sequence: { type: "integer", description: "The stable card creation sequence." },
    created_at: { type: "string", format: "date-time" },
    show_at: { anyOf: [{ type: "string", format: "date-time" }, { type: "null" }] },
    expires_at: { anyOf: [{ type: "string", format: "date-time" }, { type: "null" }] },
    created: {
      type: "boolean",
      description: "False when the idempotency key matched an existing card.",
    },
  },
  required: ["id", "sequence", "created_at", "show_at", "expires_at", "created"],
  additionalProperties: false,
};

const FEEDBACK_SCHEMA = {
  type: "object",
  properties: {
    id: { type: "string" },
    card_id: { type: "string" },
    agent_id: { type: "string" },
    agent_name: { type: "string" },
    comment: { type: "string" },
    card_title: { anyOf: [{ type: "string" }, { type: "null" }] },
    card_html: { type: "string" },
    created_at: { type: "string", format: "date-time" },
    updated_at: { type: "string", format: "date-time" },
    resolved_at: { anyOf: [{ type: "string", format: "date-time" }, { type: "null" }] },
  },
  required: [
    "id",
    "card_id",
    "agent_id",
    "agent_name",
    "comment",
    "card_title",
    "card_html",
    "created_at",
    "updated_at",
    "resolved_at",
  ],
  additionalProperties: false,
};

const TOOLS = [
  {
    name: "send_card",
    title: "Send an Agent Box card",
    description:
      "Send a small, self-contained HTML card to the connected Agent Box. Use an idempotency key when a call can be retried.",
    inputSchema: {
      type: "object",
      properties: {
        title: {
          type: "string",
          maxLength: 300,
          description: "A concise title. Put the count and verdict first when possible.",
        },
        html: {
          type: "string",
          description: "The complete card HTML. Include all data needed for offline reading.",
        },
        show_at: {
          type: "string",
          format: "date-time",
          description: "An optional ISO 8601 time when the card becomes visible.",
        },
        show_in: {
          anyOf: [{ type: "string" }, { type: "number", exclusiveMinimum: 0 }],
          description: "An optional positive relative duration before the card becomes visible.",
        },
        expires_in: {
          anyOf: [{ type: "string" }, { type: "number", exclusiveMinimum: 0 }],
          description: "The card lifetime. The default is 24h. Use never for no expiration.",
        },
        expires_at: {
          type: "string",
          format: "date-time",
          description: "An optional ISO 8601 expiration time.",
        },
        idempotency_key: {
          type: "string",
          maxLength: 255,
          description: "A unique retry key for this card operation.",
        },
        metadata: {
          type: "object",
          description: "Optional JSON metadata. It can contain at most 32 KB.",
        },
      },
      required: ["html"],
      additionalProperties: false,
    },
    outputSchema: CARD_RESULT_SCHEMA,
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: false,
      openWorldHint: false,
    },
  },
  {
    name: "list_feedback",
    title: "List Agent Box feedback",
    description:
      "List feedback for cards that this agent sent. Each item includes the card HTML snapshot and the user's comment.",
    inputSchema: {
      type: "object",
      properties: {
        status: {
          type: "string",
          enum: ["all", "unresolved", "resolved"],
          default: "unresolved",
          description: "The feedback status to return.",
        },
      },
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: {
        feedback: { type: "array", items: FEEDBACK_SCHEMA },
      },
      required: ["feedback"],
      additionalProperties: false,
    },
    annotations: {
      readOnlyHint: true,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
  },
  {
    name: "resolve_feedback",
    title: "Resolve Agent Box feedback",
    description: "Mark one feedback item for this agent as resolved.",
    inputSchema: {
      type: "object",
      properties: {
        feedback_id: {
          type: "string",
          pattern: "^feedback_[A-Z0-9]+$",
          description: "The feedback ID to resolve.",
        },
      },
      required: ["feedback_id"],
      additionalProperties: false,
    },
    outputSchema: {
      type: "object",
      properties: { feedback: FEEDBACK_SCHEMA },
      required: ["feedback"],
      additionalProperties: false,
    },
    annotations: {
      readOnlyHint: false,
      destructiveHint: false,
      idempotentHint: true,
      openWorldHint: false,
    },
  },
];

function responseHeaders(contentType?: string): Headers {
  const headers = new Headers({
    "cache-control": "no-store",
    "content-security-policy": "default-src 'none'; frame-ancestors 'none'",
    "referrer-policy": "no-referrer",
    "x-content-type-options": "nosniff",
  });
  if (contentType) headers.set("content-type", contentType);
  return headers;
}

function jsonRpcResponse(body: unknown, status = 200): Response {
  return Response.json(body, {
    status,
    headers: responseHeaders("application/json; charset=utf-8"),
  });
}

function jsonRpcError(
  id: JsonRpcId | undefined,
  code: number,
  message: string,
  data?: unknown,
): Record<string, unknown> {
  return {
    jsonrpc: "2.0",
    ...(id === undefined ? {} : { id }),
    error: { code, message, ...(data === undefined ? {} : { data }) },
  };
}

function transportError(status: number, code: number, message: string): Response {
  return jsonRpcResponse(jsonRpcError(undefined, code, message), status);
}

function isObject(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function requestId(value: unknown): JsonRpcId | undefined {
  if (typeof value === "string") return value;
  if (typeof value === "number" && Number.isInteger(value)) return value;
  return undefined;
}

function validateOrigin(request: Request): Response | null {
  const origin = request.headers.get("origin");
  if (!origin) return null;
  try {
    if (new URL(origin).origin === new URL(request.url).origin) return null;
  } catch {
    // The response below also covers a malformed Origin header.
  }
  return transportError(403, -32600, "The Origin header is not allowed.");
}

function validateProtocolVersion(request: Request): Response | null {
  const version = request.headers.get("mcp-protocol-version") ?? "2025-03-26";
  if (SUPPORTED_PROTOCOL_VERSIONS.has(version)) return null;
  return transportError(400, -32600, "The MCP-Protocol-Version header is not supported.");
}

function acceptsRequiredTypes(request: Request): boolean {
  const accept = request.headers.get("accept")?.toLowerCase() ?? "";
  return accept.includes("application/json") && accept.includes("text/event-stream");
}

function validParams(message: Record<string, unknown>): boolean {
  return message.params === undefined || isObject(message.params);
}

function parseRequest(message: Record<string, unknown>): JsonRpcRequest | null {
  if (message.jsonrpc !== "2.0" || typeof message.method !== "string" || !validParams(message)) {
    return null;
  }
  if ("id" in message && requestId(message.id) === undefined) return null;
  return message as unknown as JsonRpcRequest;
}

function isClientResponse(message: Record<string, unknown>): boolean {
  return (
    message.jsonrpc === "2.0" &&
    requestId(message.id) !== undefined &&
    typeof message.method !== "string" &&
    ("result" in message || isObject(message.error))
  );
}

function validInitializeParams(params: Record<string, unknown> | undefined): boolean {
  return (
    isObject(params) &&
    typeof params.protocolVersion === "string" &&
    isObject(params.capabilities) &&
    isObject(params.clientInfo) &&
    typeof params.clientInfo.name === "string" &&
    typeof params.clientInfo.version === "string"
  );
}

function toolCallParams(
  params: Record<string, unknown> | undefined,
): { name: string; argumentsValue: Record<string, unknown> } | null {
  if (!isObject(params) || typeof params.name !== "string") return null;
  if (params.arguments !== undefined && !isObject(params.arguments)) return null;
  return { name: params.name, argumentsValue: params.arguments ?? {} };
}

function toolResult(result: McpToolResult): Record<string, unknown> {
  const text = result.text ?? JSON.stringify(result.structuredContent);
  return {
    content: [{ type: "text", text }],
    structuredContent: result.structuredContent,
    isError: false,
  };
}

function toolError(message: string): Record<string, unknown> {
  return { content: [{ type: "text", text: message }], isError: true };
}

async function handleRequest(message: JsonRpcRequest, options: McpOptions): Promise<Response> {
  const id = message.id;
  if (id === undefined) return new Response(null, { status: 202, headers: responseHeaders() });

  if (message.method === "initialize") {
    if (!validInitializeParams(message.params)) {
      return jsonRpcResponse(jsonRpcError(id, -32602, "The initialize parameters are not valid."));
    }
    const requestedVersion = message.params!.protocolVersion as string;
    const protocolVersion = SUPPORTED_PROTOCOL_VERSIONS.has(requestedVersion)
      ? requestedVersion
      : MCP_PROTOCOL_VERSION;
    return jsonRpcResponse({
      jsonrpc: "2.0",
      id,
      result: {
        protocolVersion,
        capabilities: { tools: {} },
        serverInfo: {
          name: "agent-box",
          title: "Agent Box",
          version: "0.1.0",
          description: "Send cards and manage feedback for one Agent Box agent.",
        },
        instructions: options.instructions,
      },
    });
  }

  if (message.method === "ping") {
    return jsonRpcResponse({ jsonrpc: "2.0", id, result: {} });
  }

  if (message.method === "tools/list") {
    return jsonRpcResponse({ jsonrpc: "2.0", id, result: { tools: TOOLS } });
  }

  if (message.method === "tools/call") {
    const call = toolCallParams(message.params);
    if (!call) {
      return jsonRpcResponse(jsonRpcError(id, -32602, "The tool call parameters are not valid."));
    }
    if (!TOOLS.some((tool) => tool.name === call.name)) {
      return jsonRpcResponse(jsonRpcError(id, -32602, `Unknown tool: ${call.name}`));
    }
    try {
      const result = await options.invokeTool(call.name, call.argumentsValue);
      return jsonRpcResponse({ jsonrpc: "2.0", id, result: toolResult(result) });
    } catch (error) {
      if (error instanceof HttpError) {
        return jsonRpcResponse({
          jsonrpc: "2.0",
          id,
          result: toolError(`${error.code}: ${error.message}`),
        });
      }
      console.error(error);
      return jsonRpcResponse(jsonRpcError(id, -32603, "The tool could not complete the request."));
    }
  }

  return jsonRpcResponse(jsonRpcError(id, -32601, `Method not found: ${message.method}`));
}

export async function handleMcp(request: Request, options: McpOptions): Promise<Response> {
  const originError = validateOrigin(request);
  if (originError) return originError;
  await options.authenticate();

  if (request.method === "GET" || request.method === "DELETE") {
    return new Response(null, {
      status: 405,
      headers: new Headers({ ...Object.fromEntries(responseHeaders()), allow: "POST" }),
    });
  }
  if (request.method !== "POST") {
    return new Response(null, {
      status: 405,
      headers: new Headers({
        ...Object.fromEntries(responseHeaders()),
        allow: "GET, POST, DELETE",
      }),
    });
  }
  if (!acceptsRequiredTypes(request)) {
    return transportError(
      406,
      -32600,
      "Accept must include application/json and text/event-stream.",
    );
  }
  const contentType = request.headers.get("content-type")?.split(";", 1)[0].trim().toLowerCase();
  if (contentType !== "application/json") {
    return transportError(415, -32600, "Content-Type must be application/json.");
  }

  let messageValue: unknown;
  try {
    messageValue = JSON.parse(await readLimitedBody(request, MAX_MCP_MESSAGE_BYTES));
  } catch (error) {
    if (error instanceof HttpError) throw error;
    return transportError(400, -32700, "The request body must contain valid JSON.");
  }
  if (!isObject(messageValue)) {
    return transportError(400, -32600, "The request body must contain one JSON-RPC message.");
  }
  if (isClientResponse(messageValue)) {
    return new Response(null, { status: 202, headers: responseHeaders() });
  }

  const message = parseRequest(messageValue);
  if (!message) return transportError(400, -32600, "The JSON-RPC message is not valid.");

  if (message.method !== "initialize") {
    const versionError = validateProtocolVersion(request);
    if (versionError) return versionError;
  }
  return handleRequest(message, options);
}
