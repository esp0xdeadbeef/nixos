/**
 * Goal Extension - a simple recurring task, Codex-style /goal.
 *
 * A goal is a standing instruction. On every new turn the agent's message is
 * prefixed with the goal repeated VERBATIM (1:1, never rewritten or wrapped)
 * followed by a fixed "proof required" contract: the agent must justify, with
 * validated evidence, either that the next step is now proven done, or that it
 * is genuinely impossible.
 *
 * A goal is plain text. Nothing in it is ever treated as a file unless the
 * user explicitly marks it with `@`: `@path/to/spec.md` (relative to the
 * project root) or `@~/x/spec.md`. Only `@` tokens are read from disk at the
 * start of every turn and injected verbatim under a `[Goal file]` block. An
 * `@` file that cannot be read rejects the goal (or aborts the turn) instead
 * of running half-armed.
 *
 * Usage:
 *   /goal              show the active goal
 *   /goal <text>       set (or replace) the active goal
 *   /goal <text> file  also inline that file every turn
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
 * the per-turn wrapper is generated fresh every turn and never persisted.
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
const MAX_FILE_CHARS = 500_000;
// A file we inline is re-read on every turn; warn (not fail) past this size.
const HUGE_FILE_BYTES = 2_000_000;

// ---------------------------------------------------------------------------
// Self-continuation (/goal auto on|off)
// ---------------------------------------------------------------------------
// When armed, the extension continues the goal by itself instead of waiting for
// a human (or a tmux nudge bot) to press Enter. Guards:
//   - ON by default: `/goal <text>` arms it and kicks the first turn; never
//     persisted as "on", so a resumed session re-arms only when a goal is set;
//   - re-sends only the SHORT continuation prompt, because the goal + full file
//     are already in the transcript and re-inlining 60 KB per turn is waste;
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
const AUTO_MAX_ITERATIONS = 2000;
const AUTO_MAX_WALL_CLOCK_MS = 24 * 60 * 60 * 1000;
const STOP_WORDS = ["GOAL DONE", "GOAL BLOCKED"];

// Scratch path for goal bookkeeping (completion records, blocker notes). It is
// deliberately OUTSIDE the goal repo: /tmp/<uuid>-goal.md, one per process.
// Writing a `.goal/` dir (or any goal note) into the repo pollutes the tree and
// ends up in a commit, so the contract below points here instead.
const GOAL_NOTE_PATH = join(tmpdir(), `${randomUUID()}-goal.md`);
const NO_REPO_GOAL_DIR =
	`Do NOT create a .goal/ directory, .goal file, or any goal/completion note inside the repo — ` +
	`those are throwaway scratch and belong at ${GOAL_NOTE_PATH} (write it there if you want a note; it is never committed).`;

const AUTO_PROMPT =
	"Continue the goal. Do the next concrete step now, using tools, and do not summarize or ask permission. " +
	"You may only stop this loop by ending your turn with GOAL DONE or GOAL BLOCKED plus an escape proof. " +
	"A stop line without a proof verified by the goal extension is rejected and the loop continues. " +
	"Proof format (one per line, lowercase labels):\n" +
	"  spec: <64-hex sha256 of all the words of the goal files, concatenated in the order listed in this message:\n" +
	"        cat file1 file2 ... | sha256sum — or of the goal text itself when there are no files>\n" +
	"  solution: <git commit hash created DURING THIS RUN, in the goal repo>  (required for both escapes)\n" +
	"    GOAL DONE  — the commit implements the goal.\n" +
	"    GOAL BLOCKED — the commit documents the blocker and its message contains the word BLOCKED;\n" +
	"        there is no escape by hash alone, and an effort complaint is not a blocker.\n" +
	`Write any goal bookkeeping note to ${GOAL_NOTE_PATH} (never into the repo: no .goal/ dir, no .goal file).\n` +
	"Compute the spec hash yourself with the exact cat|sha256sum command; do not invent hex. " +
	"Commit before claiming either escape; the extension verifies the commit exists, is new, and matches the escape.";

interface GoalState {
	goal: string | null;
}

// Fixed per-turn contract. Generated fresh each turn, NEVER stored in `goal`
// and never folded back into the persisted value.
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
}

// Read every goal file in full. Throws on a file that cannot be read, so the
// turn aborts instead of running with the goal half-inlined.
function loadGoalFiles(cwd: string, goal: string | null): LoadedFile[] {
	const files: LoadedFile[] = [];
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
		let text = readFileSync(abs, "utf8");
		let truncated = false;
		if (text.length > MAX_FILE_CHARS) {
			text = text.slice(0, MAX_FILE_CHARS);
			truncated = true;
		}
		files.push({ path: token, abs, bytes: st.size, text, truncated });
	}
	return files;
}

function fileHeader(files: LoadedFile[]): string {
	if (files.length === 0) return "";
	const blocks = files.map((f) => {
		const head = `${FILE_MARKER} ${f.path} (${f.abs}) — ${f.bytes} bytes${f.truncated ? `, TRUNCATED to the first ${MAX_FILE_CHARS} chars` : ""}, read in full now:`;
		return `${head}\n<<<FILE ${f.path}\n${f.text}\nFILE ${f.path}>>>`;
	});
	return [
		"This file is part of the goal. It is reprinted here in full on every turn, so it is already open:",
		"read it here, apply it as written, and do not claim you cannot see it or need to re-read it.",
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
function specHash(cwd: string, goal: string | null): string {
	const h = createHash("sha256");
	const files = loadGoalFiles(cwd, goal);
	if (files.length > 0) {
		for (const f of files) h.update(f.text);
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

// The short continuation prompt plus the live list of words to hash, so the
// escape instructions always name the exact files. Used both for the settle
// continuation and for the self-start kick when /goal auto is armed.
function autoPrompt(goal: string | null, _cwd: string): string {
	const files = goalFileTokens(goal);
	const hashTargets =
		files.length > 0
			? `\n\nWords to hash for the spec proof — run exactly:\n  cat ${files.join(" ")} | sha256sum`
			: `\n\nWords to hash for the spec proof — run exactly:\n  printf '%s' '${goal}' | sha256sum`;
	return `${AUTO_PROMPT}${hashTargets}`;
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
		const entries = ctx.sessionManager.getBranch();
		for (let i = entries.length - 1; i >= 0; i--) {
			const entry = entries[i] as { type?: string; customType?: string; data?: GoalState };
			if (entry.type === "custom" && entry.customType === ENTRY_TYPE) {
				goal = entry.data?.goal ?? null;
				break;
			}
		}
	}

	// The verbatim goal plus the fixed proof contract. Nothing here is ever
	// written back into `goal`, so the stored text stays 1:1 with what you typed.
	function goalHeader(_cwd: string): string {
		const files = goalFileTokens(goal);
		const note =
			files.length > 0
				? `\n\nThis goal names ${files.length} file(s): ${files.join(", ")}. Their full content is printed below the contract, reprinted fresh every turn.`
				: "";
		return `${INPUT_MARKER} GOAL (verbatim):\n${goal}${note}\n\n${PROOF_CONTRACT}`;
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
						? `Auto-continue armed (default ON; max ${AUTO_MAX_ITERATIONS} turns / 24 h). Stop it with /goal auto off. It stops only on "${STOP_WORDS[0]}" or "${STOP_WORDS[1]}" with a proof verified by the extension.`
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
						`Files inlined each turn: ${goalFileTokens(goal).join(", ") || "(none)"}`,
						`Auto-continue: ${autoRun ? `on (default), ${autoIterations}/${AUTO_MAX_ITERATIONS} turns` : "off (/goal auto to re-arm)"}`,
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
				(f) => `\n  ${f.path} (${f.abs}) — ${f.bytes} bytes, inlined every turn`,
			);
			const huge = files.filter((f) => f.bytes > HUGE_FILE_BYTES);
			ctx.ui.notify(
				`Goal set (auto-continue ON — /goal auto off to stop):\n${goal}${fileLines.length ? `\n\nInlined each turn:${fileLines.join("")}` : ""}` +
					(huge.length ? `\n\nWarning: ${huge.length} file(s) over ${HUGE_FILE_BYTES} bytes — this will be expensive every turn.` : ""),
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

	// Prepend the verbatim goal + proof contract + the full text of every goal
	// file to every new user turn. Files are re-read from disk here, so an edit
	// made between turns is picked up with no /goal re-issue.
	pi.on("input", async (event, ctx) => {
		lastCtx = ctx;
		if (!goal) return;
		// Skip only extension-injected input; interactive and rpc are real users.
		if (event.source === "extension") return;
		// Idempotency: never wrap a turn that already carries the wrapper.
		if (event.text.includes(INPUT_MARKER)) return;
		// Slash commands are handled by their own handler; do not wrap them.
		if (event.text.trimStart().startsWith("/")) return;

		// A broken goal file must not degrade into a silent no-op turn.
		const files = loadGoalFiles(ctx.cwd, goal);
		const body = files.length > 0 ? `\n\n${fileHeader(files)}` : "";
		return { action: "transform", text: `${goalHeader(ctx.cwd)}${body}\n\n${event.text}` };
	});

	// Track the assistant's own words so auto-continue can stop when the agent
	// says it is finished or blocked. Last non-empty assistant text wins.
	pi.on("message_end", (event) => {
		const msg = event.message as { role?: string; content?: unknown } | undefined;
		if (!msg || msg.role !== "assistant") return;
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
	pi.on("agent_before_settle", (_event) => {
		if (!autoRun || !goal) return;

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
			return {
				continue: true,
				entries: [
					{
						type: "custom_message" as const,
						customType: ENTRY_TYPE,
						display: true,
						content:
							`Your escape was REJECTED by the goal extension: ${reasons.join("; ")}. ` +
							`For GOAL BLOCKED the blocker must be real and committed: write the blocker analysis to ${GOAL_NOTE_PATH}, ` +
							`commit the repo work (or a commit whose message contains BLOCKED), and give that commit as the solution line. ` +
							`Never write a .goal/ dir or a goal note into the repo — only ${GOAL_NOTE_PATH}. ` +
							`An effort complaint ("too much work", "context too small") is not a blocker. ` +
							`For GOAL DONE the solution commit must implement the goal and be created during this run.\n\n` +
							`${AUTO_PROMPT}`,
					},
				],
			};
		}

		autoIterations += 1;
		const elapsed = autoStartedAt ? Date.now() - autoStartedAt : 0;
		if (autoIterations > AUTO_MAX_ITERATIONS || elapsed > AUTO_MAX_WALL_CLOCK_MS) {
			autoRun = false;
			autoStartedAt = 0;
			if (lastCtx) {
				updateStatus(lastCtx);
				lastCtx.ui.notify(
					`Auto-continue stopped by cap: ${autoIterations} turns / ${Math.round(elapsed / 3600000)} h. Re-arm with /goal auto.`,
					"warning",
				);
			}
			return;
		}
		if (lastCtx) updateStatus(lastCtx);

		return {
			continue: true,
			entries: [
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
