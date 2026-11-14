/**
 * Goal Extension - a simple recurring task, Codex-style /goal.
 *
 * A goal is a standing instruction. It is injected as a SYSTEM PROMPT SECTION
 * (verbatim, 1:1, never rewritten) together with a fixed "proof required"
 * contract: the agent must justify, with validated evidence, either that the
 * next step is now proven done, or that it is genuinely impossible.
 *
 * Why the system prompt and not a user message: a user-message wrapper lands in
 * the transcript, so every copy is replayed on every request AND fed into the
 * compaction summarization request as conversation. That is what made this
 * extension blow up long sessions - a real one carried 61 copies (~111 KB) of
 * the goal wrapper into context and into the compactor. A prompt section costs
 * one copy in the leading system message, never enters the conversation, and is
 * not summarized by compaction; after a compaction the section is still there
 * because the prompt is rebuilt from the live goal on every request.
 *
 * A goal is plain text. Nothing in it is ever treated as a file unless the
 * user explicitly marks it with `@`: `@path/to/spec.md` (relative to the
 * project root) or `@~/x/spec.md`. Only `@` tokens are read from disk for each
 * request and injected verbatim into the prompt under a `[Goal file]` block. An
 * `@` file that cannot be read rejects the goal (or aborts the turn) instead
 * of running half-armed. A file body is capped (MAX_FILE_CHARS per file, a
 * MAX_TOTAL_FILE_CHARS total) and the cut is stated in the prompt, because a
 * whole multi-hundred-KB file in the prompt on every request is exactly the
 * kind of cost this extension has to stay away from.
 *
 * Usage:
 *   /goal              show the active goal
 *   /goal <text>       set (or replace) the active goal
 *   /goal <text> file  also inline that file into the prompt
 *   /goal status       goal + which files are inlined + auto state
 *   /goal auto         arm self-continuation (already ON by default)
 *   /goal auto off     stop continuing automatically
 *   /goal clear        clear the active goal
 *   /goal off          same as clear
 *
 * Self-continuation replaces the "nudge the pane with a dot every 10 seconds"
 * loop: with auto armed the extension requests the next turn itself and keeps
 * going up to 2000 turns / 24 h. It does not stop on a bare marker, and a hash
 * alone is not an escape: GOAL DONE and GOAL BLOCKED both require
 *   - spec: sha256 of all the goal's words (recomputed here), and
 *   - solution: a git commit created DURING THIS RUN in the goal repo; for
 *     GOAL BLOCKED its message must document the blocker (contain BLOCKED).
 * An effort complaint is not a blocker. ON by default (setting a goal starts
 * the loop), never persisted on.
 *
 * The goal is stored in the session, so it follows the active branch and is
 * restored on resume / branch navigation. Only the raw goal text is stored;
 * the prompt section that carries it is rebuilt for each request and never
 * persisted, so it cannot accumulate in the transcript.
 */

import { execFileSync } from "node:child_process";
import { createHash, randomUUID } from "node:crypto";
import { existsSync, readFileSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, isAbsolute, join, resolve } from "node:path";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const ENTRY_TYPE = "goal";
const STATUS_KEY = "goal";
const INPUT_MARKER = "[Goal]";
const FILE_MARKER = "[Goal file]";

// Cap per file so one runaway path cannot eat the whole window. Past this the
// file is inlined as far as the cap and the cut is stated explicitly, so the
// agent knows it is reading a truncated document, never a silently partial one.
//
// This used to be 500_000 chars (~125k tokens). Because the file body is
// re-injected on every wrapped turn, one `@big.md` burned ~125k tokens per turn
// and blew a 1M window in a handful of turns. The goal loop does not need the
// whole file in context: it needs the goal, and the agent can `read` the file
// itself when a step actually depends on it. So the inline budget is small and
// the rest is a pointer.
const MAX_FILE_CHARS = 16_000;
// Total budget across ALL goal files, so ten files cannot each spend the per-
// file cap. Files are inlined in listed order until this is exhausted.
const MAX_TOTAL_FILE_CHARS = 32_000;
// Files are re-read on every request; warn (not fail) past this size.
const HUGE_FILE_BYTES = 256_000;

// Auto-continue budget. These are the user's original caps and are deliberately
// unrelated to the context fix: with the goal in the system prompt and
// continuations pruned to one, a long loop no longer grows the transcript, so
// there is no reason to shorten how long the user wants it to run.
const AUTO_MAX_ITERATIONS = 2000;
const AUTO_MAX_WALL_CLOCK_MS = 24 * 60 * 60 * 1000;

// ---------------------------------------------------------------------------
// Self-continuation (/goal auto on|off)
// ---------------------------------------------------------------------------
// When armed, the extension continues the goal by itself instead of waiting for
// a human (or a tmux nudge bot) to press Enter. Guards:
//   - ON by default: `/goal <text>` arms it and kicks the first turn; never
//     persisted as "on", so a resumed session re-arms only when a goal is set;
//   - the goal + contract live in the system prompt, so a continuation message
//     is a one-liner and never restates them;
//   - stops on a hard iteration cap (2000 turns) and a wall-clock cap (24 h);
//   - stops when the goal is cleared or the session switches.
//
// Escape contract (GAMP-style: nothing is OK until evidenced, and the evidence
// is re-verified here, not taken on the agent's word):
//   - GOAL DONE  requires `spec: <sha256>` = the hash of ALL the words of the
//     goal + its inlined files (recomputed by this extension from disk) and,
//     in a git repo, `solution: <commit>` = a commit that actually exists.
//   - GOAL BLOCKED requires `spec: <sha256>` plus the blocker text.
// A stop line without a verified proof is rejected and the loop continues.
const STOP_WORDS = ["GOAL DONE", "GOAL BLOCKED"];

// Scratch path for goal bookkeeping (completion records, blocker notes). It is
// deliberately OUTSIDE the goal repo: /tmp/<uuid>-goal.md, one per process.
// Writing a `.goal/` dir (or any goal note) into the repo pollutes the tree and
// ends up in a commit, so the contract below points here instead.
const GOAL_NOTE_PATH = join(tmpdir(), `${randomUUID()}-goal.md`);
const NO_REPO_GOAL_DIR =
	`Do NOT create a .goal/ directory, .goal file, or any goal/completion note inside the repo — ` +
	`those are throwaway scratch and belong at ${GOAL_NOTE_PATH} (write it there if you want a note; it is never committed).`;

// The escape contract lives in the system prompt (PROOF_CONTRACT below), so the
// continuation messages only need to say "keep going" plus the exact hash
// command for this goal. They are the only entries this extension puts in the
// transcript, so they are deliberately one line each.
const AUTO_CONTINUE = "Continue the goal: do the next concrete step now, using tools. Do not summarize or ask permission.";

interface GoalState {
	goal: string | null;
}

// Fixed per-turn contract, part of the system prompt. The escape proof format
// lives here too: the prompt is rebuilt for every request and survives
// compaction, so the agent always has the exact rules without the extension
// re-writing them into the transcript.
const PROOF_CONTRACT = [
	"PROOF REQUIRED (answer this for every turn, before doing anything else):",
	"1. Restate the exact next step you are about to complete.",
	"2. State either (a) PROVEN DONE, or (b) IMPOSSIBLE, and show the evidence:",
	"   - PROVEN DONE: the concrete check/command/output that validates it was",
	"     actually executed. Include the command and its real output, not a claim.",
	"   - IMPOSSIBLE: a validated argument for why it cannot be completed here",
	"     (what you tried, the exact error/blocker, and why no workaround exists).",
	"3. Only after that evidence, proceed. If you cannot supply evidence, say so",
	"   explicitly instead of claiming progress.",
	NO_REPO_GOAL_DIR,
	"",
	"ESCAPE (only when auto-continue is on): end your turn with GOAL DONE or GOAL BLOCKED",
	"plus a proof. Format, one per line, lowercase labels:",
	"  spec: <64-hex sha256 of the goal's words, or of its files concatenated — the exact",
	"        command is given in each continuation message>",
	"  solution: <git commit hash created DURING THIS RUN, in the goal repo>",
	"    GOAL DONE — the commit implements the goal.",
	"    GOAL BLOCKED — the commit documents the blocker and its message contains BLOCKED.",
	"A stop line without a verified proof is rejected and the loop continues. An effort",
	"complaint (\"too much work\", \"context too small\") is not a blocker.",
].join("\n");

// ---------------------------------------------------------------------------
// Goal files
// ---------------------------------------------------------------------------

// A goal file is OPT-IN and only ever an `@path` token. Everything else in
// the goal is text: no extension sniffing, no slash detection, no glob/URL
// heuristics. `/goal URS / FS` is text; `/goal @spec.md` inlines a file.
function looksLikePath(token: string): boolean {
	const t = token.trim();
	return t.startsWith("@") && t.length > 1;
}

function normalizePathToken(token: string): string {
	let t = token.trim();
	t = t.replace(/^[`'"*_(<\[]+/, "").replace(/[`'"*_>)\],.;:]+$/, "");
	if (t.startsWith("@")) t = t.slice(1);
	if (t.startsWith("~/")) t = `${process.env.HOME ?? ""}${t.slice(1)}`;
	return t;
}

function goalFileTokens(goal: string | null, _cwd?: string): string[] {
	if (!goal) return [];
	const out: string[] = [];
	for (const raw of goal.split(/\s+/)) {
		if (!looksLikePath(raw)) continue;
		const p = normalizePathToken(raw);
		if (p && !out.includes(p)) out.push(p);
	}
	return out;
}

interface LoadedFile {
	path: string;
	abs: string;
	bytes: number;
	text: string;
	truncated: boolean;
	// Chars left out of `text` because of the per-file or total budget.
	omittedChars: number;
}

// Per-turn file cache. `specHash()`, `repoDir()` and the input wrapper all need
// the same files; before this cache each settle re-read every goal file from
// disk up to three times.
let fileCache: { key: string; files: LoadedFile[] } | null = null;

function cacheKey(cwd: string, goal: string | null): string {
	return `${cwd}\u0000${goal ?? ""}`;
}

function loadGoalFiles(cwd: string, goal: string | null): LoadedFile[] {
	const key = cacheKey(cwd, goal);
	if (fileCache && fileCache.key === key) return fileCache.files;
	const files = readGoalFiles(cwd, goal);
	fileCache = { key, files };
	return files;
}

// Read every goal file. Throws on a file that cannot be read, so the turn
// aborts instead of running with the goal half-inlined. Each file is cut at the
// per-file cap and the whole set at the total cap; both cuts are reported.
function readGoalFiles(cwd: string, goal: string | null): LoadedFile[] {
	const files: LoadedFile[] = [];
	let budget = MAX_TOTAL_FILE_CHARS;
	for (const token of goalFileTokens(goal, cwd)) {
		const abs = isAbsolute(token) ? token : resolve(cwd, token);
		if (!existsSync(abs)) {
			throw new Error(
				`goal file not found: ${token} (resolved to ${abs}). Fix the path with /goal, or remove it.`,
			);
		}
		const st = statSync(abs);
		if (!st.isFile()) {
			throw new Error(`goal path is not a file: ${token} (resolved to ${abs}).`);
		}
		const full = readFileSync(abs, "utf8");
		const take = Math.min(full.length, Math.max(0, Math.min(MAX_FILE_CHARS, budget)));
		budget -= take;
		files.push({
			path: token,
			abs,
			bytes: st.size,
			text: full.slice(0, take),
			truncated: take < full.length,
			omittedChars: full.length - take,
		});
	}
	return files;
}

function fileHeader(files: LoadedFile[]): string {
	if (files.length === 0) return "";
	const blocks = files.map((f) => {
		const cut = f.truncated
			? ` — TRUNCATED: ${f.omittedChars} chars omitted here; use the read tool on this path for the rest`
			: "";
		const head = `${FILE_MARKER} ${f.path} (${f.abs}) — ${f.bytes} bytes${cut}`;
		return `${head}\n<<<FILE ${f.path}\n${f.text}\nFILE ${f.path}>>>`;
	});
	return [
		"These files are part of the goal. They are already open below; apply them as written.",
		"Do not claim you cannot see them or need to re-read them unless a step needs text past a TRUNCATED cut.",
		...blocks,
	].join("\n\n");
}

// ---------------------------------------------------------------------------
// Escape proof (GAMP-style verification of the agent's claim)
// ---------------------------------------------------------------------------
// Scratch notes the agent wants to keep (completion records, blocker analyses)
// go to /tmp/<uuid>-goal.md via GOAL_NOTE_PATH — never into the repo as a
// `.goal/` directory, which used to end up committed alongside real work.

// sha256 of "all the words", reproducible by the agent with one command:
//   with goal files:  cat file1 file2 ... | sha256sum   (in the listed order)
//   without files:    printf '%s' '<goal text>' | sha256sum
// Recomputing from disk here means the agent cannot fake the hash.
//
// This must hash the FULL file bytes, exactly like `cat | sha256sum`, and never
// the truncated inline copy: the file body is capped for context reasons, so
// hashing the capped text would guarantee a mismatch for every large goal file.
function specHash(cwd: string, goal: string | null): string {
	const h = createHash("sha256");
	const tokens = goalFileTokens(goal, cwd);
	if (tokens.length > 0) {
		for (const token of tokens) {
			const abs = isAbsolute(token) ? token : resolve(cwd, token);
			h.update(readFileSync(abs));
		}
	} else if (goal) {
		h.update(goal);
	}
	return h.digest("hex");
}

// The repo a solution commit must live in: the goal file's repo, else cwd.
function repoDir(cwd: string, goal: string | null): string | null {
	const files = loadGoalFiles(cwd, goal);
	const anchor = files.length > 0 ? dirname(files[0].abs) : cwd;
	try {
		return execFileSync("git", ["-C", anchor, "rev-parse", "--show-toplevel"], {
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		}).trim() || null;
	} catch {
		return null;
	}
}

interface CommitInfo {
	hash: string;
	ct: number; // committer timestamp, seconds
	msg: string;
}

// Read a commit's timestamp + message, or null if it does not exist.
function commitInfo(repo: string, hash: string): CommitInfo | null {
	if (!repo || !/^[0-9a-f]{7,40}$/i.test(hash)) return null;
	try {
		const out = execFileSync("git", ["-C", repo, "show", "-s", "--format=%ct%x00%s", `${hash}^{commit}`], {
			encoding: "utf8",
			stdio: ["ignore", "pipe", "ignore"],
		});
		const [ctRaw, ...msg] = out.split("\0");
		const ct = Number.parseInt(ctRaw, 10);
		if (!Number.isFinite(ct)) return null;
		return { hash, ct, msg: msg.join("\0").trim() };
	} catch {
		return null;
	}
}

function commitExists(repo: string, hash: string): boolean {
	if (!repo || !/^[0-9a-f]{7,40}$/i.test(hash)) return false;
	try {
		execFileSync("git", ["-C", repo, "cat-file", "-e", `${hash}^{commit}`], {
			stdio: ["ignore", "ignore", "ignore"],
		});
		return true;
	} catch {
		return false;
	}
}

interface EscapeProof {
	kind: "done" | "blocked";
	spec: string | null;
	solution: string | null;
}

// Parse the agent's own last words for a stop line + proof fields.
function parseEscape(text: string): EscapeProof | null {
	const up = text.toUpperCase();
	const doneIdx = up.lastIndexOf(STOP_WORDS[0]);
	const blockedIdx = up.lastIndexOf(STOP_WORDS[1]);
	let kind: "done" | "blocked";
	let at: number;
	if (doneIdx === -1 && blockedIdx === -1) return null;
	if (doneIdx > blockedIdx) {
		kind = "done";
		at = doneIdx;
	} else {
		kind = "blocked";
		at = blockedIdx;
	}
	const after = text.slice(at);
	const spec = /(?:^|\n)\s*spec\s*:\s*([0-9a-fA-F]{64})\b/.exec(after);
	const sol = /(?:^|\n)\s*solution\s*:\s*([0-9a-fA-F]{7,40})\b/.exec(after);
	return {
		kind,
		spec: spec ? spec[1].toLowerCase() : null,
		solution: sol ? sol[1].toLowerCase() : null,
	};
}

// The continuation message plus the exact hash command for this goal. This is
// the ONLY thing the extension writes into the transcript per auto-turn, so it
// stays one short line; the goal, the contract and the file bodies live in the
// system prompt instead (see before_agent_start).
function autoPrompt(goal: string | null, _cwd: string): string {
	const files = goalFileTokens(goal);
	const hashCommand =
		files.length > 0
			? `cat ${files.join(" ")} | sha256sum`
			: `printf '%s' '${goal?.replace(/'/g, "'\\''") ?? ""}' | sha256sum`;
	return `${AUTO_CONTINUE}\n\nspec hash: ${hashCommand}`;
}

export default function goalExtension(pi: ExtensionAPI) {
	let goal: string | null = null;
	// Auto-continue is ON by default: setting a goal with /goal starts the loop
	// without a separate /goal auto. Still session-local and never persisted, so
	// a resumed session does not silently resume burning tokens — it re-arms only
	// when a goal is set (or /goal auto is issued) in that session.
	let autoRun = true;
	let autoIterations = 0;
	let autoStartedAt = 0;
	// Goal state is now carried by the system prompt section, so the old
	// "already inlined this run" bookkeeping is gone.
	// Context size seen at the last assistant message, for the soft cap.
	let lastContextTokens = 0;

	function elapsedNow(): number {
		return autoStartedAt ? Date.now() - autoStartedAt : 0;
	}

	// Return the ids of every goal continuation prompt this run already appended.
	// They are persisted custom_messages that the model replays on every request,
	// so a long loop pays for all of them at once. We keep only the newest and
	// omit the rest with context_edit (raw history and the UI keep everything).
	function priorPromptEntryIds(ctx: ExtensionContext | null): string[] {
		if (!ctx) return [];
		const ids: string[] = [];
		try {
			for (const entry of ctx.sessionManager.getBranch()) {
				const e = entry as { type?: string; customType?: string; id?: string };
				if (e.type === "custom_message" && e.customType === ENTRY_TYPE && e.id) ids.push(e.id);
			}
		} catch {
			return [];
		}
		return ids;
	}

	// Omit every previously appended continuation, because this handler is about to
	// append a fresh one. `previousEntryIds` are ids that already exist in the
	// branch; entries drafted in this same handler have no id yet and cannot be
	// targeted, which is exactly why the caller passes the pre-existing list.
	function pruneSuperseded(previousEntryIds: string[]): Array<{ type: "context_edit"; targetId: string; replacement: null }> {
		return previousEntryIds.map((id) => ({ type: "context_edit" as const, targetId: id, replacement: null }));
	}

	// Central stop check: turn cap and wall clock. No context-based stop here: the
	// user's caps are the only stopping policy this extension adds.
	function stopByCap(elapsed: number): boolean {
		let why: string | null = null;
		if (autoIterations > AUTO_MAX_ITERATIONS) {
			why = `cap ${AUTO_MAX_ITERATIONS} turns`;
		} else if (elapsed > AUTO_MAX_WALL_CLOCK_MS) {
			why = `cap ${Math.round(AUTO_MAX_WALL_CLOCK_MS / 3600000)} h`;
		}
		if (!why) return false;
		autoRun = false;
		autoStartedAt = 0;
		if (lastCtx) {
			updateStatus(lastCtx);
			lastCtx.ui.notify(
				`Auto-continue stopped by ${why} after ${autoIterations} turns. Re-arm with /goal auto; /goal clear drops the goal.`,
				"warning",
			);
		}
		return true;
	}
	// The last assistant text seen this run, used to detect the stop words.
	let lastAssistantText = "";
	// The settle hook has no ctx argument; remember the latest one for status.
	let lastCtx: ExtensionContext | null = null;

	function persist(): void {
		pi.appendEntry<GoalState>(ENTRY_TYPE, { goal });
	}

	function updateStatus(ctx: ExtensionContext): void {
		if (!ctx.hasUI) return;
		if (!goal) {
			ctx.ui.setStatus(STATUS_KEY, undefined);
			return;
		}
		const oneLine = goal.replace(/\s+/g, " ");
		const short = oneLine.length > 48 ? `${oneLine.slice(0, 47)}…` : oneLine;
		const files = goalFileTokens(goal);
		const fileSuffix = files.length > 0 ? ` [+${files.length} file${files.length === 1 ? "" : "s"}]` : "";
		const autoSuffix = autoRun ? ` ↻${autoIterations}/${AUTO_MAX_ITERATIONS}` : "";
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("accent", `🎯 ${short}${fileSuffix}${autoSuffix}`));
	}

	function restore(ctx: ExtensionContext): void {
		goal = null;
		autoRun = true;
		autoIterations = 0;
		autoStartedAt = 0;
		lastContextTokens = 0;
		fileCache = null;
		const entries = ctx.sessionManager.getBranch();
		for (let i = entries.length - 1; i >= 0; i--) {
			const entry = entries[i] as { type?: string; customType?: string; data?: GoalState };
			if (entry.type === "custom" && entry.customType === ENTRY_TYPE) {
				goal = entry.data?.goal ?? null;
				break;
			}
		}
	}

	// Strip a wrapper if the user pastes a previously-wrapped turn as the goal.
	// This keeps the stored goal 1:1 and prevents the header from accumulating.
	function unwrapGoal(text: string): string {
		let t = text;
		const marker = `${INPUT_MARKER} GOAL (verbatim):\n`;
		const idx = t.indexOf(marker);
		if (idx !== -1) t = t.slice(idx + marker.length);
		const oldMarker = `${INPUT_MARKER} Active goal:\n`;
		const oldIdx = t.indexOf(oldMarker);
		if (oldIdx !== -1) t = t.slice(oldIdx + oldMarker.length);
		const contract = `\n\n${PROOF_CONTRACT}`;
		const cIdx = t.indexOf(contract);
		if (cIdx !== -1) t = t.slice(0, cIdx);
		// The injected file block starts right after the contract.
		const fIdx = t.indexOf(FILE_MARKER);
		if (fIdx !== -1) t = t.slice(0, fIdx);
		return t.trim();
	}

	pi.registerCommand("goal", {
		description: "Set, show, or clear a recurring goal (/goal <text> | /goal clear)",
		getArgumentCompletions: (prefix) => {
			const options = ["clear", "off", "auto", "auto off", "status"];
			const matches = options.filter((o) => o.startsWith(prefix.trim()));
			return matches.length > 0 ? matches.map((value) => ({ value, label: value })) : null;
		},
		handler: async (args, ctx) => {
			const text = args.trim();
			const lower = text.toLowerCase();

			if (!text) {
				if (goal) {
					ctx.ui.notify(`Active goal:\n${goal}`, "info");
				} else {
					ctx.ui.notify("No active goal. Use /goal <text> to set one.", "info");
				}
				return;
			}

			// /goal auto        arm self-continuation
			// /goal auto off     disarm
			// /goal status       show goal + auto state
			if (lower === "auto" || lower === "auto on" || lower === "auto off") {
				if (!goal) {
					ctx.ui.notify("No active goal. Set one first: /goal <text> [file]", "warning");
					return;
				}
				const on = lower !== "auto off";
				autoRun = on;
				autoIterations = 0;
				autoStartedAt = on ? Date.now() : 0;
				updateStatus(ctx);
				ctx.ui.notify(
					on
						? `Auto-continue armed (default ON; max ${AUTO_MAX_ITERATIONS} turns / ${Math.round(AUTO_MAX_WALL_CLOCK_MS / 3600000)} h). Stop it with /goal auto off. It stops only on "${STOP_WORDS[0]}" or "${STOP_WORDS[1]}" with a proof verified by the extension.`
						: "Auto-continue disarmed.",
					"info",
				);
				// Self-start: arming while idle kicks the first turn, so no
				// external dot/nudge is needed to get the loop moving.
				if (on && ctx.isIdle()) {
					pi.sendMessage(
						{
							customType: ENTRY_TYPE,
							content: autoPrompt(goal, ctx.cwd),
							display: true,
						},
						{ triggerTurn: true },
					);
				}
				return;
			}

			if (lower === "status") {
				ctx.ui.notify(
					[
						`Goal: ${goal ?? "(none)"}`,
						`Files inlined once per run: ${goalFileTokens(goal).join(", ") || "(none)"}`,
						`Auto-continue: ${autoRun ? `on (default), ${autoIterations}/${AUTO_MAX_ITERATIONS} turns, context ${lastContextTokens} tokens` : "off (/goal auto to re-arm)"}`,
					].join("\n"),
					"info",
				);
				return;
			}

			if (lower === "clear" || lower === "off" || lower === "none") {
				if (!goal) {
					ctx.ui.notify("No active goal.", "info");
					return;
				}
				goal = null;
				autoRun = false;
				autoIterations = 0;
				fileCache = null;
				persist();
				updateStatus(ctx);
				ctx.ui.notify("Goal cleared.", "info");
				return;
			}

			// Store exactly what was typed (after unwrapping a pasted turn).
			const next = unwrapGoal(text);

			// Fail now, not on every turn, if a named file is not readable.
			let files: LoadedFile[];
			try {
				files = loadGoalFiles(ctx.cwd, next);
			} catch (err) {
				ctx.ui.notify(`Goal not set — ${(err as Error).message}`, "error");
				return;
			}

			goal = next;
			// Auto-continue is ON by default: setting a goal arms the loop in the
			// same step, anchored now so the solution commit must be from this run.
			autoRun = true;
			autoIterations = 0;
			autoStartedAt = Date.now();
			persist();
			updateStatus(ctx);
			const fileLines = files.map(
				(f) =>
					`\n  ${f.path} (${f.abs}) — ${f.bytes} bytes` +
					(f.truncated ? `, first ${f.text.length} chars inlined (${f.omittedChars} omitted — the agent reads the rest itself)` : ""),
			);
			const huge = files.filter((f) => f.bytes > HUGE_FILE_BYTES);
			ctx.ui.notify(
				`Goal set (auto-continue ON — /goal auto off to stop):\n${goal}${fileLines.length ? `\n\nInlined once per run:${fileLines.join("")}` : ""}` +
					(huge.length
						? `\n\nWarning: ${huge.length} file(s) over ${HUGE_FILE_BYTES} bytes. They are capped at ${MAX_FILE_CHARS} chars (${MAX_TOTAL_FILE_CHARS} total), so the agent must read the rest with its own tools.`
						: ""),
				"info",
			);
			// Self-start when idle, so /goal <text> alone begins the loop with no
			// extra /goal auto and no external nudge.
			if (ctx.isIdle()) {
				pi.sendMessage(
					{ customType: ENTRY_TYPE, content: autoPrompt(goal, ctx.cwd), display: true },
					{ triggerTurn: true },
				);
			}
		},
	});

	// The user's own text passes through untouched. The goal is not injected
	// here: it lives in the system prompt (see before_agent_start), so a user turn
	// costs exactly what the user typed and the goal is never duplicated into the
	// transcript or into the compaction input. This hook only validates the goal
	// files, so a path deleted between turns fails now instead of on every turn.
	pi.on("input", async (event, ctx) => {
		lastCtx = ctx;
		if (!goal) return;
		// Skip only extension-injected input; interactive and rpc are real users.
		if (event.source === "extension") return;
		// Slash commands are handled by their own handler; do not touch them.
		if (event.text.trimStart().startsWith("/")) return;

		// The goal + proof contract live in the SYSTEM PROMPT (see the
		// before_agent_start hook below), not in the user turn. Wrapping the text
		// here would write another copy of the goal into the transcript on every
		// message, and the transcript is exactly what compaction has to summarize.
		// The only thing this hook still does is validate the goal files early, so
		// a deleted file fails this turn instead of silently arming a broken goal.
		// Validate the goal files now, then drop the cache so the request that follows
		// re-reads them and picks up any edit made since the last turn.
		loadGoalFiles(ctx.cwd, goal);
		fileCache = null;
	});

	// The goal, its proof contract and its file bodies are injected as a SYSTEM
	// PROMPT SECTION, not as a user message.
	//
	// This is the whole point of the design. A user-message wrapper is persisted
	// in the transcript, which means every copy is (a) replayed to the model on
	// every request, (b) fed into compaction's summarization request as
	// "conversation", and (c) left behind in the compacted summary as duplicated
	// goal prose. Measured on a real session: 61 copies of the wrapper, ~111 KB.
	//
	// A prompt section instead costs exactly one copy in the leading system
	// message, is diffed by pi (so it is a cache hit once written), never enters
	// the conversation, and is therefore never summarized by compaction. On
	// compaction the section is still present, because the system prompt is
	// rebuilt for every request from the live goal.
	pi.on("before_agent_start", (event, ctx) => {
		if (!goal) return;
		// Keep the transcript clean: nothing this extension adds goes into it.
		let section = `\n\nThe following is the user's standing goal, restated by the goal extension. It applies to every turn until it is cleared.\n\n${INPUT_MARKER} GOAL (verbatim):\n${goal}\n\n${PROOF_CONTRACT}`;
		const files = goalFileTokens(goal);
		if (files.length > 0) {
			// Files are read fresh here, so an edit between turns is picked up with no
			// /goal re-issue. A file that cannot be read fails the turn loudly.
			const loaded = loadGoalFiles(ctx.cwd, goal);
			section += `\n\n${fileHeader(loaded)}`;
		}
		event.systemPromptOptions.sections.goal = section;
	});

	// Track the assistant's own words so auto-continue can stop when the agent
	// says it is finished or blocked. Last non-empty assistant text wins.
	pi.on("message_end", (event) => {
		const msg = event.message as { role?: string; content?: unknown } | undefined;
		if (!msg || msg.role !== "assistant") return;
		// Track context size for the soft cap in agent_before_settle.
		const usage = (msg as { usage?: { input?: number; cacheRead?: number; cacheWrite?: number } }).usage;
		if (usage) {
			lastContextTokens = (usage.input ?? 0) + (usage.cacheRead ?? 0) + (usage.cacheWrite ?? 0);
		}
		const content = msg.content;
		const text = Array.isArray(content)
			? content
					.filter((b): b is { type: string; text: string } => !!b && typeof b === "object" && (b as { type?: string }).type === "text")
					.map((b) => b.text)
					.join("\n")
			: typeof content === "string"
				? content
				: "";
		if (text.trim()) lastAssistantText = text;
	});

	// Self-continuation: when armed, ask for one more turn at the point where pi
	// would otherwise settle. Every exit path disarms, so nothing can loop.
	// The only accepted escapes are the verified proof lines; a bare GOAL DONE /
	// GOAL BLOCKED is rejected and the loop continues with the rejection reason.
	pi.on("agent_before_settle", (event) => {
		if (!autoRun || !goal) return;

		// Every entry this extension appends is persisted and replayed to the model
		// for the rest of the session. Keep only the newest continuation live and
		// omit the older ones via context_edit, so N turns cost one instruction,
		// not N. Drafts in event.entries have no id yet, so only already-persisted
		// ids are targeted.
		const prune = pruneSuperseded(priorPromptEntryIds(lastCtx));

		const proof = parseEscape(lastAssistantText);
		if (proof) {
			const cwd = lastCtx?.cwd ?? process.cwd();
			const want = specHash(cwd, goal);
			const specOk = proof.spec === want;
			const repo = repoDir(cwd, goal);
			const runStartSec = autoStartedAt > 0 ? Math.floor(autoStartedAt / 1000) : 0;
			const sol = proof.solution ? commitInfo(repo ?? "", proof.solution) : null;
			const solExists = sol !== null;
			const solFresh = solExists && (runStartSec === 0 || sol.ct >= runStartSec - 1);
			const solSaysBlocked = solExists && /BLOCK/i.test(sol.msg);

			// No commit-based escapes outside a git repo; hash alone is nothing.
			const doneOk =
				proof.kind === "done" && specOk && repo !== null && solExists && solFresh;
			const blockedOk =
				proof.kind === "blocked" && specOk && repo !== null && solExists && solFresh && solSaysBlocked;

			if (doneOk || blockedOk) {
				autoRun = false;
				autoStartedAt = 0;
				if (lastCtx) {
					updateStatus(lastCtx);
					lastCtx.ui.notify(
						doneOk
							? `Auto-continue stopped: GOAL DONE proof verified (spec hash + solution commit ${sol?.hash}).`
							: `Auto-continue stopped: GOAL BLOCKED accepted (spec hash + blocker commit ${sol?.hash}).`,
						"info",
					);
				}
				return;
			}

			// Rejected escape: tell the agent exactly why and keep it in the loop.
			const reasons: string[] = [];
			if (!specOk) {
				reasons.push(
					`spec hash rejected (yours: ${proof.spec ?? "missing"}; it does not match the words on disk — run the exact cat|sha256sum command)`,
				);
			}
			if (repo === null) {
				reasons.push(`no git repo at ${cwd} — commit the work and the blocker, then escape with a solution line`);
			} else {
				if (!solExists) {
					reasons.push(`solution missing (commit your work first, then give its hash)`);
				} else if (!solFresh) {
					reasons.push(`solution ${sol.hash} is not from this run — the commit must be created after auto-continue was armed`);
				}
				if (proof.kind === "blocked" && solExists && !solSaysBlocked) {
					reasons.push(`blocker commit ${sol.hash} does not document a blocker — its message must contain BLOCKED`);
				}
			}
			autoIterations += 1;
			if (lastCtx) updateStatus(lastCtx);
			if (stopByCap(elapsedNow())) return;
			// The rejection is its own message; it must stay small. The goal and the
			// escape contract are in the system prompt, so the rejection only names the
			// reason plus the hash command, never a second copy of the instructions.
			return {
				continue: true,
				entries: [
					...prune,
					{
						type: "custom_message" as const,
						customType: ENTRY_TYPE,
						display: true,
						content:
							`Escape REJECTED: ${reasons.join("; ")}. ` +
							`Commit real work (blocker commits must say BLOCKED in the message), then give spec: + solution:. ` +
							`Never write .goal/ or a note into the repo — only ${GOAL_NOTE_PATH}. ` +
							`An effort complaint is not a blocker.\n\n` +
							autoPrompt(goal, cwd),
					},
				],
			};
		}

		autoIterations += 1;
		if (lastCtx) updateStatus(lastCtx);
		if (stopByCap(elapsedNow())) return;

		return {
			continue: true,
			entries: [
				...prune,
				{
					type: "custom_message" as const,
					customType: ENTRY_TYPE,
					content: autoPrompt(goal, lastCtx?.cwd ?? process.cwd()),
					display: true,
				},
			],
		};
	});

	pi.on("session_start", async (_event, ctx) => {
		lastCtx = ctx;
		restore(ctx);
		updateStatus(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		lastCtx = ctx;
		restore(ctx);
		updateStatus(ctx);
	});
}
