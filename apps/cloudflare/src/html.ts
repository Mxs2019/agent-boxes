import { decodeHTML } from "entities";
import { HttpError } from "./errors";
import { MAX_CARD_BYTES } from "./http";

export function validateCardHtml(input: string): string {
  if (!input.trim()) throw new HttpError(400, "missing_html", "The card HTML must not be empty.");
  if (new TextEncoder().encode(input).byteLength > MAX_CARD_BYTES) {
    throw new HttpError(
      413,
      "card_too_large",
      `Card HTML must be at most ${MAX_CARD_BYTES} bytes.`,
    );
  }
  return input;
}

class PlainTextHandler implements HTMLRewriterDocumentContentHandlers {
  readonly nodes: string[] = [];
  private node = "";

  text(text: Text): void {
    this.node += text.text;
    if (!text.lastInTextNode) return;
    if (this.node.trim()) this.nodes.push(this.node.trim());
    this.node = "";
  }
}

export async function makePlainText(html: string): Promise<string> {
  const readableHtml = html
    .replace(/<script\b[^>]*>[\s\S]*?<\/script\s*>/gi, " ")
    .replace(/<style\b[^>]*>[\s\S]*?<\/style\s*>/gi, " ")
    .replace(/<template\b[^>]*>[\s\S]*?<\/template\s*>/gi, " ");
  const handler = new PlainTextHandler();
  const response = new Response(readableHtml, { headers: { "content-type": "text/html" } });
  await new HTMLRewriter().onDocument(handler).transform(response).text();
  return decodeHTML(handler.nodes.join(" ")).replace(/\s+/g, " ").trim();
}
