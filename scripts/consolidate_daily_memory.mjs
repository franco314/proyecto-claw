#!/usr/bin/env node

import fs from "node:fs/promises";
import path from "node:path";

const SECTION_ORDER = ["Active Topics", "Decisions", "Pending", "Useful Facts"];
const SECTION_LIMITS = {
  "Active Topics": 4,
  Decisions: 6,
  Pending: 6,
  "Useful Facts": 6,
};

const TRIVIAL_MESSAGES = new Set([
  "hola",
  "buen dia",
  "buenos dias",
  "buenas",
  "dale",
  "ok",
  "oka",
  "si",
  "no",
  "joya",
  "gracias",
  "gracias!",
  "buenas noches",
  "buenas tardes",
  "prueba",
  "prueba local",
  "funcionas",
  "funcionas?",
]);

const DECISION_RE =
  /\b(decid|mantener|usar|crear|activar|desactivar|prefer|prioridad|debe|quiero|quiere|vamos a|queda|quedo|eleg|fuente de verdad|sqlite|reset horario|solo hoy|solo ayer)\b/i;
const PENDING_RE =
  /\b(pendient|falta|revis|verific|deploy|probar|instalar|hacer|investig|armar|seguir|despues|luego|hay que|follow[- ]?up|todo\b|to-do)\b/i;
const FACT_RE =
  /\b(estamos en|timezone|villa urquiza|buenos aires|franco|siempre|nunca|prefier|correccion|correg|sin audios|sin tts|whatsapp|river|grupo|dm)\b/i;

function parseArgs(argv) {
  const args = {
    messages: 24,
    timezone: "America/Buenos_Aires",
    json: false,
    dryRun: false,
  };

  for (let i = 0; i < argv.length; i += 1) {
    const token = argv[i];
    const next = argv[i + 1];
    switch (token) {
      case "--agent-id":
        args.agentId = next;
        i += 1;
        break;
      case "--session-key":
        args.sessionKey = next;
        i += 1;
        break;
      case "--workspace":
        args.workspace = next;
        i += 1;
        break;
      case "--sessions-dir":
        args.sessionsDir = next;
        i += 1;
        break;
      case "--session-file":
        args.sessionFile = next;
        i += 1;
        break;
      case "--timestamp":
        args.timestamp = next;
        i += 1;
        break;
      case "--timezone":
        args.timezone = next;
        i += 1;
        break;
      case "--messages":
        args.messages = Number(next);
        i += 1;
        break;
      case "--json":
        args.json = true;
        break;
      case "--dry-run":
        args.dryRun = true;
        break;
      default:
        throw new Error(`Unknown argument: ${token}`);
    }
  }

  if (!args.workspace) {
    throw new Error("Missing required argument: --workspace");
  }
  if (!args.sessionsDir && !args.sessionFile) {
    throw new Error("Missing required argument: --sessions-dir or --session-file");
  }
  if (!Number.isFinite(args.messages) || args.messages <= 0) {
    throw new Error("--messages must be a positive number");
  }

  return args;
}

function formatDateInTimezone(date, timezone) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const map = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${map.year}-${map.month}-${map.day}`;
}

function normalizeItem(text) {
  return text
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")
    .replace(/[`*_>#]/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/[.?!,:;]+$/g, "")
    .toLowerCase();
}

function cleanConversationText(text) {
  let cleaned = String(text ?? "").replace(/\r/g, "");
  cleaned = cleaned.replace(/^\[[^\]]+\]\s*/gm, "");
  cleaned = cleaned.replace(
    /Conversation info \(untrusted metadata\):\s*```json[\s\S]*?```/gim,
    "",
  );
  cleaned = cleaned.replace(/^System:.*$/gim, "");
  cleaned = cleaned.replace(/A scheduled reminder has been triggered\.[\s\S]*$/gim, "");
  cleaned = cleaned.replace(
    /A new session was started via \/new or \/reset[\s\S]*$/gim,
    "",
  );
  cleaned = cleaned.replace(/^Please relay this reminder.*$/gim, "");
  cleaned = cleaned.replace(/^Current time:.*$/gim, "");
  cleaned = cleaned.replace(/^session\.reset$/gim, "");
  return cleaned.replace(/\n{3,}/g, "\n\n").trim();
}

function isTrivialText(text) {
  const normalized = normalizeItem(text);
  if (!normalized) {
    return true;
  }
  if (TRIVIAL_MESSAGES.has(normalized)) {
    return true;
  }
  const words = normalized.split(" ").filter(Boolean);
  if (words.length <= 2 && words.every((word) => TRIVIAL_MESSAGES.has(word))) {
    return true;
  }
  return false;
}

function sanitizeItem(text) {
  const cleaned = String(text ?? "")
    .replace(/^\[[^\]]+\]\s*/g, "")
    .replace(/\s+/g, " ")
    .replace(/^[*-]\s*/, "")
    .trim();
  if (!cleaned) {
    return "";
  }
  if (cleaned.length <= 180) {
    return cleaned;
  }
  return `${cleaned.slice(0, 177).trimEnd()}...`;
}

function splitCandidates(text) {
  const lines = String(text ?? "")
    .split(/\n+/)
    .map((line) => line.trim())
    .filter(Boolean);
  const parts = [];
  for (const line of lines) {
    const segments = line
      .split(/(?<=[.?!])\s+/)
      .map((segment) => segment.trim())
      .filter(Boolean);
    if (segments.length === 0) {
      parts.push(line);
      continue;
    }
    parts.push(...segments);
  }
  return parts
    .map((item) => sanitizeItem(item))
    .filter((item) => item.length >= 8 && item.length <= 180);
}

function classifyCandidate(candidate, role) {
  const normalized = normalizeItem(candidate);
  if (!normalized || isTrivialText(candidate)) {
    return null;
  }
  if (role === "user" && /^(soy|me llamo|mi nombre es)\b/i.test(candidate.trim())) {
    return "Useful Facts";
  }
  if (
    normalized.includes("scheduled reminder") ||
    normalized.includes("new session started") ||
    normalized === "session reset"
  ) {
    return null;
  }
  if (DECISION_RE.test(normalized)) {
    return "Decisions";
  }
  if (PENDING_RE.test(normalized)) {
    return "Pending";
  }
  if (FACT_RE.test(normalized)) {
    return "Useful Facts";
  }
  if (role === "user") {
    return "Active Topics";
  }
  return null;
}

function pushUnique(target, section, item) {
  const cleaned = sanitizeItem(item);
  if (!cleaned) {
    return;
  }
  const normalized = normalizeItem(cleaned);
  if (!normalized) {
    return;
  }
  const entries = target.get(section);
  if (!entries.some((entry) => normalizeItem(entry) === normalized)) {
    entries.push(cleaned);
  }
}

async function readJsonFile(filePath) {
  try {
    return JSON.parse(await fs.readFile(filePath, "utf-8"));
  } catch {
    return null;
  }
}

async function resolveSessionContext(args) {
  if (args.sessionFile) {
    return {
      sessionFile: path.resolve(args.sessionFile),
      sessionId: null,
    };
  }

  const sessionsDir = path.resolve(args.sessionsDir);
  const sessionsJson = await readJsonFile(path.join(sessionsDir, "sessions.json"));
  const entry =
    (args.sessionKey && sessionsJson && typeof sessionsJson === "object"
      ? sessionsJson[args.sessionKey]
      : null) || null;

  if (entry?.sessionFile) {
    return {
      sessionFile: path.resolve(entry.sessionFile),
      sessionId: entry.sessionId ?? null,
    };
  }

  if (entry?.sessionId) {
    const candidate = path.join(sessionsDir, `${entry.sessionId}.jsonl`);
    try {
      await fs.access(candidate);
      return { sessionFile: candidate, sessionId: entry.sessionId };
    } catch {
      // Fall through to best-effort discovery below.
    }
  }

  const files = await fs.readdir(sessionsDir);
  const jsonlFiles = files
    .filter((name) => name.endsWith(".jsonl") && !name.includes(".reset."))
    .sort();
  if (jsonlFiles.length === 0) {
    return { sessionFile: null, sessionId: entry?.sessionId ?? null };
  }

  return {
    sessionFile: path.join(sessionsDir, jsonlFiles[jsonlFiles.length - 1]),
    sessionId: entry?.sessionId ?? null,
  };
}

async function loadRecentMessages(sessionFile, limit) {
  const raw = await fs.readFile(sessionFile, "utf-8");
  const messages = [];
  for (const line of raw.split("\n")) {
    const trimmed = line.trim();
    if (!trimmed) {
      continue;
    }
    let entry;
    try {
      entry = JSON.parse(trimmed);
    } catch {
      continue;
    }
    if (entry.type !== "message" || !entry.message) {
      continue;
    }
    const msg = entry.message;
    const role = msg.role;
    if (role !== "user" && role !== "assistant") {
      continue;
    }
    if (role === "user" && msg.provenance?.kind === "inter_session") {
      continue;
    }
    const textBlock = Array.isArray(msg.content)
      ? msg.content.find((part) => part.type === "text")?.text
      : typeof msg.content === "string"
        ? msg.content
        : "";
    if (!textBlock || String(textBlock).startsWith("/")) {
      continue;
    }
    const cleaned = cleanConversationText(textBlock);
    if (!cleaned) {
      continue;
    }
    messages.push({
      role,
      text: cleaned,
      timestamp: msg.timestamp ?? entry.timestamp ?? null,
    });
  }
  return messages.slice(-limit);
}

function initSections() {
  return new Map(SECTION_ORDER.map((section) => [section, []]));
}

function buildSectionsFromMessages(messages) {
  const sections = initSections();
  const relevantUserMessages = messages.filter(
    (message) => message.role === "user" && !isTrivialText(message.text),
  );

  for (const message of messages) {
    const candidates = splitCandidates(message.text);
    if (candidates.length === 0 && message.role === "user" && !isTrivialText(message.text)) {
      candidates.push(sanitizeItem(message.text));
    }
    for (const candidate of candidates) {
      const section = classifyCandidate(candidate, message.role);
      if (!section) {
        continue;
      }
      pushUnique(sections, section, candidate);
    }
  }

  return {
    sections,
    relevantUserMessages: relevantUserMessages.length,
    hasRelevantActivity: relevantUserMessages.length > 0,
  };
}

function parseExistingMemory(content) {
  const sections = initSections();
  let currentSection = null;
  const lines = String(content ?? "").split(/\r?\n/);

  for (const line of lines) {
    const sectionMatch = /^##\s+(.*)\s*$/.exec(line.trim());
    if (sectionMatch) {
      const title = sectionMatch[1].trim();
      currentSection = SECTION_ORDER.includes(title) ? title : null;
      continue;
    }
    const itemMatch = /^-\s+(.*)\s*$/.exec(line.trim());
    if (!itemMatch) {
      continue;
    }
    const item = sanitizeItem(itemMatch[1]);
    if (!item) {
      continue;
    }
    pushUnique(sections, currentSection ?? "Useful Facts", item);
  }

  return sections;
}

function mergeSections(existingSections, newSections) {
  const merged = initSections();
  for (const section of SECTION_ORDER) {
    for (const item of existingSections.get(section) ?? []) {
      pushUnique(merged, section, item);
    }
    for (const item of newSections.get(section) ?? []) {
      pushUnique(merged, section, item);
    }
  }

  const occupied = new Set();
  for (const section of ["Decisions", "Pending", "Useful Facts", "Active Topics"]) {
    const deduped = [];
    for (const item of merged.get(section)) {
      const normalized = normalizeItem(item);
      if (occupied.has(normalized)) {
        continue;
      }
      occupied.add(normalized);
      deduped.push(item);
    }
    const limit = SECTION_LIMITS[section];
    merged.set(section, deduped.slice(-limit));
  }

  return merged;
}

function renderMemory(dateStr, sections) {
  const lines = [`# ${dateStr}`];
  for (const section of SECTION_ORDER) {
    const items = sections.get(section) ?? [];
    if (items.length === 0) {
      continue;
    }
    lines.push("", `## ${section}`);
    for (const item of items) {
      lines.push(`- ${item}`);
    }
  }
  return `${lines.join("\n").trim()}\n`;
}

function countSectionItems(sections) {
  return Object.fromEntries(
    SECTION_ORDER.map((section) => [section, (sections.get(section) ?? []).length]),
  );
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const now = args.timestamp ? new Date(args.timestamp) : new Date();
  if (Number.isNaN(now.valueOf())) {
    throw new Error(`Invalid timestamp: ${args.timestamp}`);
  }

  const dateStr = formatDateInTimezone(now, args.timezone);
  const workspaceDir = path.resolve(args.workspace);
  const memoryDir = path.join(workspaceDir, "memory");
  const memoryFile = path.join(memoryDir, `${dateStr}.md`);
  const sessionContext = await resolveSessionContext(args);

  if (!sessionContext.sessionFile) {
    return {
      status: "skipped",
      reason: "session_file_not_found",
      agentId: args.agentId ?? null,
      sessionKey: args.sessionKey ?? null,
      memoryFile,
    };
  }

  const messages = await loadRecentMessages(sessionContext.sessionFile, args.messages);
  const built = buildSectionsFromMessages(messages);
  if (!built.hasRelevantActivity) {
    return {
      status: "skipped",
      reason: "no_relevant_activity",
      agentId: args.agentId ?? null,
      sessionKey: args.sessionKey ?? null,
      sessionFile: sessionContext.sessionFile,
      memoryFile,
      relevantMessages: 0,
    };
  }

  let existingContent = "";
  try {
    existingContent = await fs.readFile(memoryFile, "utf-8");
  } catch {
    existingContent = "";
  }

  const merged = mergeSections(parseExistingMemory(existingContent), built.sections);
  const rendered = renderMemory(dateStr, merged);

  if (existingContent.trim() === rendered.trim()) {
    return {
      status: "skipped",
      reason: "no_changes",
      agentId: args.agentId ?? null,
      sessionKey: args.sessionKey ?? null,
      sessionFile: sessionContext.sessionFile,
      memoryFile,
      relevantMessages: built.relevantUserMessages,
      sections: countSectionItems(merged),
    };
  }

  if (!args.dryRun) {
    await fs.mkdir(memoryDir, { recursive: true });
    await fs.writeFile(memoryFile, rendered, "utf-8");
  }

  return {
    status: args.dryRun ? "dry_run" : existingContent ? "updated" : "written",
    agentId: args.agentId ?? null,
    sessionKey: args.sessionKey ?? null,
    sessionFile: sessionContext.sessionFile,
    memoryFile,
    relevantMessages: built.relevantUserMessages,
    sections: countSectionItems(merged),
  };
}

try {
  const result = await main();
  if (process.argv.includes("--json")) {
    process.stdout.write(`${JSON.stringify(result)}\n`);
  } else if (result.status === "skipped") {
    process.stdout.write(`skipped: ${result.reason ?? "unknown"}\n`);
  } else {
    process.stdout.write(`${result.status}: ${result.memoryFile}\n`);
  }
} catch (error) {
  const message = error instanceof Error ? error.message : String(error);
  process.stderr.write(`${message}\n`);
  process.exitCode = 1;
}
