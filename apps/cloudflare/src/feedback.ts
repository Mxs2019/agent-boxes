import { ulid } from "ulid";
import { authenticateAccount, authenticateAgent, authenticateFeedbackReader } from "./auth";
import { HttpError } from "./errors";
import { readLimitedBody } from "./http";
import type { Feedback, FeedbackRow } from "./types";

const MAX_FEEDBACK_BYTES = 16 * 1024;
const MAX_FEEDBACK_CHARACTERS = 5_000;

interface FeedbackPayload {
  comment?: unknown;
}

interface FeedbackCardRow {
  id: string;
  agent_id: string | null;
  title: string | null;
  html: string;
}

function toFeedback(row: FeedbackRow): Feedback {
  return {
    id: row.id,
    card_id: row.card_id,
    agent_id: row.agent_id,
    agent_name: row.agent_name,
    comment: row.comment,
    card_title: row.card_title,
    card_html: row.card_html,
    created_at: new Date(row.created_at * 1_000).toISOString(),
    updated_at: new Date(row.updated_at * 1_000).toISOString(),
    resolved_at: row.resolved_at === null ? null : new Date(row.resolved_at * 1_000).toISOString(),
  };
}

async function readComment(request: Request): Promise<string> {
  const body = await readLimitedBody(request, MAX_FEEDBACK_BYTES);
  let payload: FeedbackPayload;
  try {
    payload = JSON.parse(body) as FeedbackPayload;
  } catch {
    throw new HttpError(400, "invalid_json", "The request body must contain valid JSON.");
  }
  if (!payload || Array.isArray(payload) || typeof payload !== "object") {
    throw new HttpError(400, "invalid_json", "The request body must contain a JSON object.");
  }
  if (typeof payload.comment !== "string") {
    throw new HttpError(400, "invalid_feedback", "comment is required and must be a string.");
  }
  const comment = payload.comment.trim();
  if (!comment) {
    throw new HttpError(400, "invalid_feedback", "comment must not be empty.");
  }
  if (comment.length > MAX_FEEDBACK_CHARACTERS) {
    throw new HttpError(
      400,
      "invalid_feedback",
      `comment must be at most ${MAX_FEEDBACK_CHARACTERS} characters.`,
    );
  }
  return comment;
}

async function findFeedback(
  db: D1Database,
  feedbackId: string,
  scopeColumn: "account_id" | "agent_id",
  scopeId: string,
): Promise<FeedbackRow | null> {
  return db
    .prepare(
      `SELECT feedback.*, agents.name AS agent_name
       FROM feedback
       JOIN agents ON agents.id = feedback.agent_id
       WHERE feedback.id = ?1 AND feedback.${scopeColumn} = ?2`,
    )
    .bind(feedbackId, scopeId)
    .first<FeedbackRow>();
}

export async function createFeedback(
  request: Request,
  db: D1Database,
  cardId: string,
): Promise<Feedback> {
  const account = await authenticateAccount(request, db);
  const comment = await readComment(request);
  const card = await db
    .prepare("SELECT id, agent_id, title, html FROM cards WHERE id = ?1 AND account_id = ?2")
    .bind(cardId, account.id)
    .first<FeedbackCardRow>();
  if (!card) throw new HttpError(404, "card_not_found", "The card does not exist.");
  if (!card.agent_id) {
    throw new HttpError(
      400,
      "card_has_no_agent",
      "Feedback is available only for cards that an agent created.",
    );
  }

  const feedbackId = `feedback_${ulid()}`;
  const now = Math.floor(Date.now() / 1_000);
  await db
    .prepare(
      `INSERT INTO feedback (
         id, account_id, card_id, agent_id, comment, card_title, card_html,
         created_at, updated_at, resolved_at
       ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?8, NULL)`,
    )
    .bind(feedbackId, account.id, card.id, card.agent_id, comment, card.title, card.html, now)
    .run();

  const feedback = await findFeedback(db, feedbackId, "account_id", account.id);
  if (!feedback) throw new Error("The created feedback could not be read.");
  return toFeedback(feedback);
}

export async function listFeedback(request: Request, db: D1Database): Promise<Feedback[]> {
  const reader = await authenticateFeedbackReader(request, db);
  const status = new URL(request.url).searchParams.get("status") ?? "all";
  if (!["all", "unresolved", "resolved"].includes(status)) {
    throw new HttpError(
      400,
      "invalid_feedback_status",
      "status must be all, unresolved, or resolved.",
    );
  }
  const statusClause =
    status === "unresolved"
      ? "AND feedback.resolved_at IS NULL"
      : status === "resolved"
        ? "AND feedback.resolved_at IS NOT NULL"
        : "";
  const scopeColumn = reader.agent ? "agent_id" : "account_id";
  const scopeId = reader.agent?.id ?? reader.account.id;
  const result = await db
    .prepare(
      `SELECT feedback.*, agents.name AS agent_name
       FROM feedback
       JOIN agents ON agents.id = feedback.agent_id
       WHERE feedback.${scopeColumn} = ?1 ${statusClause}
       ORDER BY feedback.created_at ASC, feedback.id ASC`,
    )
    .bind(scopeId)
    .all<FeedbackRow>();
  return result.results.map(toFeedback);
}

export async function updateFeedback(
  request: Request,
  db: D1Database,
  feedbackId: string,
): Promise<Feedback> {
  const account = await authenticateAccount(request, db);
  const comment = await readComment(request);
  const now = Math.floor(Date.now() / 1_000);
  const updated = await db
    .prepare(
      `UPDATE feedback SET comment = ?1, updated_at = ?2
       WHERE id = ?3 AND account_id = ?4
       RETURNING id`,
    )
    .bind(comment, now, feedbackId, account.id)
    .first<{ id: string }>();
  if (!updated) throw new HttpError(404, "feedback_not_found", "The feedback does not exist.");

  const feedback = await findFeedback(db, feedbackId, "account_id", account.id);
  if (!feedback) throw new Error("The updated feedback could not be read.");
  return toFeedback(feedback);
}

export async function deleteFeedback(
  request: Request,
  db: D1Database,
  feedbackId: string,
): Promise<void> {
  const account = await authenticateAccount(request, db);
  const result = await db
    .prepare("DELETE FROM feedback WHERE id = ?1 AND account_id = ?2")
    .bind(feedbackId, account.id)
    .run();
  if (result.meta.changes === 0) {
    throw new HttpError(404, "feedback_not_found", "The feedback does not exist.");
  }
}

export async function resolveFeedback(
  request: Request,
  db: D1Database,
  feedbackId: string,
): Promise<Feedback> {
  const { agent } = await authenticateAgent(request, db);
  const now = Math.floor(Date.now() / 1_000);
  await db
    .prepare(
      `UPDATE feedback SET resolved_at = COALESCE(resolved_at, ?1), updated_at = ?1
       WHERE id = ?2 AND agent_id = ?3`,
    )
    .bind(now, feedbackId, agent.id)
    .run();

  const feedback = await findFeedback(db, feedbackId, "agent_id", agent.id);
  if (!feedback) throw new HttpError(404, "feedback_not_found", "The feedback does not exist.");
  return toFeedback(feedback);
}
