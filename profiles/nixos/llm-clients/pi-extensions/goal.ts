/**
 * Goal Extension - a simple recurring task, Codex-style /goal.
 *
 * A goal is a standing instruction. On every new turn the agent's message is
 * prefixed with the goal repeated VERBATIM (1:1, never rewritten or wrapped)
 * followed by a fixed "proof required" contract: the agent must justify, with
 * validated evidence, either that the next step is now proven done, or that it
 * is genuinely impossible.
 *
 * Usage:
 *   /goal              show the active goal
 *   /goal <text>       set (or replace) the active goal
 *   /goal clear        clear the active goal
 *   /goal off          same as clear
 *
 * The goal is stored in the session, so it follows the active branch and is
 * restored on resume / branch navigation. Only the raw goal text is stored;
 * the per-turn wrapper is generated fresh every turn and never persisted.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const ENTRY_TYPE = "goal";
const STATUS_KEY = "goal";
const INPUT_MARKER = "[Goal]";

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
].join("\n");

export default function goalExtension(pi: ExtensionAPI) {
	let goal: string | null = null;

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
		ctx.ui.setStatus(STATUS_KEY, ctx.ui.theme.fg("accent", `🎯 ${short}`));
	}

	function restore(ctx: ExtensionContext): void {
		goal = null;
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
	function goalHeader(): string {
		return `${INPUT_MARKER} GOAL (verbatim):\n${goal}\n\n${PROOF_CONTRACT}`;
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
		return t.trim();
	}

	pi.registerCommand("goal", {
		description: "Set, show, or clear a recurring goal (/goal <text> | /goal clear)",
		getArgumentCompletions: (prefix) => {
			const options = ["clear", "off"];
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

			if (lower === "clear" || lower === "off" || lower === "none") {
				if (!goal) {
					ctx.ui.notify("No active goal.", "info");
					return;
				}
				goal = null;
				persist();
				updateStatus(ctx);
				ctx.ui.notify("Goal cleared.", "info");
				return;
			}

			// Store exactly what was typed (after unwrapping a pasted turn).
			goal = unwrapGoal(text);
			persist();
			updateStatus(ctx);
			ctx.ui.notify(`Goal set:\n${goal}`, "info");
		},
	});

	// Prepend the verbatim goal + proof contract to every new user turn.
	pi.on("input", (event) => {
		if (!goal) return;
		// Skip only extension-injected input; interactive and rpc are real users.
		if (event.source === "extension") return;
		// Idempotency: never wrap a turn that already carries the wrapper.
		if (event.text.includes(INPUT_MARKER)) return;
		// Slash commands are handled by their own handler; do not wrap them.
		if (event.text.trimStart().startsWith("/")) return;
		return { action: "transform", text: `${goalHeader()}\n\n${event.text}` };
	});

	pi.on("session_start", async (_event, ctx) => {
		restore(ctx);
		updateStatus(ctx);
	});

	pi.on("session_tree", async (_event, ctx) => {
		restore(ctx);
		updateStatus(ctx);
	});
}
