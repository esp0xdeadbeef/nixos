/**
 * Chrome CDP Extension - browser automation over the DevTools protocol.
 *
 * Owns a dedicated, agent-only Chrome instance started in a detached tmux
 * session with remote debugging bound to loopback, then drives it over CDP
 * with raw JSON-RPC on a WebSocket. No npm dependencies: Node's global
 * WebSocket and fetch are used directly.
 *
 * Usage:
 *   /chrome            start (or restart) the browser and show status
 *   /chrome stop       kill the managed browser
 *   /chrome status     show status
 *
 * Tools (all of them start the browser on demand):
 *   browser_navigate     open a URL in a new tab and return readable text
 *   browser_snapshot     readable text + interactive elements of a tab
 *   browser_click        click an element by CSS selector, text, or coords
 *   browser_type         type into a field (optionally submitting)
 *   browser_eval         run JavaScript in the page
 *   browser_screenshot   capture a PNG screenshot
 *   browser_tabs         list / select / close tabs
 *   browser_close        stop the managed browser (manual, never automatic)
 *
 * The browser is intentionally left running after a pi session ends: it lives
 * in its own detached tmux session, so the next session (and the human) can
 * continue where the last one stopped. Stop it explicitly with browser_close
 * or `/chrome stop`.
 *
 * Environment overrides:
 *   PI_CHROME_BIN         chrome binary (default: google-chrome-stable)
 *   PI_CHROME_PROFILE     profile dir (default: /tmp/codex-chrome-devtools-active)
 *   PI_CHROME_PORT        remote debugging port (default: 9222)
 *   PI_CHROME_TMUX         tmux session name (default: pi-chrome-cdp)
 */

import { mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { spawn, spawnSync } from "node:child_process";
import { mkdtemp, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const CHROME_BIN = process.env.PI_CHROME_BIN ?? "google-chrome-stable";
const PROFILE_DIR = process.env.PI_CHROME_PROFILE ?? "/tmp/codex-chrome-devtools-active";
const PORT = Number(process.env.PI_CHROME_PORT ?? "9222");
const TMUX_SESSION = process.env.PI_CHROME_TMUX ?? "pi-chrome-cdp";

const HOST = "127.0.0.1";
const BASE = `http://${HOST}:${PORT}`;
const LOCK_FILES = ["SingletonLock", "SingletonSocket", "SingletonCookie"];

const START_TIMEOUT_MS = 25_000;
/** Stale `pkill`/`rm`/`sleep` chain handed to the tmux session; it must outlive the
 * longest start delay so the freshly launched shell is never killed afterwards. */
const PRE_LAUNCH_DELAY_MS = 1_000;
const NAV_TIMEOUT_MS = 30_000;
const CDP_TIMEOUT_MS = 20_000;
const MAX_TEXT_CHARS = 20_000;

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function hasTmux(): boolean {
	return spawnSync("tmux", ["-V"], { stdio: "ignore" }).status === 0;
}

function shellQuote(value: string): string {
	return `'${value.replace(/'/g, `'\\''`)}'`;
}

function escapeRegex(value: string): string {
	return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

/**
 * Kill only the managed Chrome. The regex starts with `[c]` so it cannot match
 * the shell command line that runs it, and no other Chrome uses this profile.
 */
function pkillCommand(): string {
	const pattern = `[c]hrome.*--user-data-dir=${escapeRegex(PROFILE_DIR)}`;
	return `pkill -TERM -f ${shellQuote(pattern)} || true`;
}

function chromeCommand(): string {
	return [
		CHROME_BIN,
		`--user-data-dir=${shellQuote(PROFILE_DIR)}`,
		`--remote-debugging-address=${HOST}`,
		`--remote-debugging-port=${PORT}`,
		"--no-first-run",
		"--no-default-browser-check",
		"--disable-session-crashed-bubble",
		"--ozone-platform=x11",
	].join(" ");
}

function cleanupCommand(): string {
	const files = LOCK_FILES.map((name) => `"${PROFILE_DIR}/${name}"`).join(" ");
	return `rm -f ${files}`;
}

async function killManagedBrowser(): Promise<void> {
	await mkdir(PROFILE_DIR, { recursive: true }).catch(() => {});
	// Drop the tmux wrapper first so it does not race with the pkill below.
	spawnSync("tmux", ["kill-session", "-t", TMUX_SESSION], { stdio: "ignore" });
	spawnSync("bash", ["-lc", pkillCommand()], { stdio: "ignore" });
	await sleep(PRE_LAUNCH_DELAY_MS);
	spawnSync("bash", ["-lc", cleanupCommand()], { stdio: "ignore" });
}

async function browserVersion(): Promise<{ Browser: string; webSocketDebuggerUrl: string } | null> {
	try {
		const res = await fetch(`${BASE}/json/version`, { signal: AbortSignal.timeout(1500) });
		if (!res.ok) return null;
		return (await res.json()) as { Browser: string; webSocketDebuggerUrl: string };
	} catch {
		return null;
	}
}

async function launchInTmux(): Promise<string> {
	// Chrome is backgrounded so its output can be redirected to a log file, then
	// `wait` keeps the pane (and therefore the session) alive for as long as Chrome
	// runs. Without `wait` the session exits instantly and takes Chrome with it.
	const foreground = `${chromeCommand()} > /tmp/pi-chrome-cdp.log 2>&1 &\nwait`;
	await mkdir(PROFILE_DIR, { recursive: true });

	if (hasTmux()) {
		spawnSync("tmux", ["kill-session", "-t", TMUX_SESSION], { stdio: "ignore" });
		const started = spawnSync(
			"tmux",
			["new-session", "-d", "-s", TMUX_SESSION, "-c", PROFILE_DIR, "bash", "-lc", foreground],
			{ encoding: "utf8" },
		);
		if (started.status !== 0) {
			throw new Error(`tmux failed to start the browser: ${started.stderr || started.stdout || "unknown error"}`);
		}
		return `tmux session ${TMUX_SESSION}`;
	}

	// No tmux available: detach with setsid so the browser outlives this process.
	const child = spawn("bash", ["-lc", `exec ${chromeCommand()}`], { detached: true, stdio: "ignore" });
	child.unref();
	return "detached process (tmux not found)";
}

/** Ensure the managed browser is running and CDP answers; returns launch info. */
async function ensureBrowser(restart = false): Promise<{ launched: string; version: string; alreadyRunning: boolean }> {
	const running = await browserVersion();
	if (running && !restart) {
		return { launched: "already running", version: running.Browser, alreadyRunning: true };
	}
	if (restart) await killManagedBrowser();
	const launched = await launchInTmux();

	const deadline = Date.now() + START_TIMEOUT_MS;
	while (Date.now() < deadline) {
		const version = await browserVersion();
		if (version) return { launched, version: version.Browser, alreadyRunning: false };
		await sleep(250);
	}

	const hint = hasTmux() ? ` Check it with: tmux attach -t ${TMUX_SESSION}` : "";
	throw new Error(
		`Chrome did not expose CDP on ${BASE} within ${START_TIMEOUT_MS / 1000}s.` +
			` Is DISPLAY set and ${CHROME_BIN} installed?${hint}`,
	);
}

// ---------------------------------------------------------------------------
// minimal CDP client
// ---------------------------------------------------------------------------

type CdpEventHandler = (params: any) => void;

class CdpConnection {
	private static cache = new Map<string, Promise<CdpConnection>>();
	private nextId = 1;
	private pending = new Map<number, { resolve: (v: any) => void; reject: (e: Error) => void }>();
	private listeners = new Map<string, Set<CdpEventHandler>>();
	private closed = false;

	private constructor(private ws: WebSocket) {
		this.ws.addEventListener("message", (event: MessageEvent) => {
			let msg: any;
			try {
				msg = JSON.parse(typeof event.data === "string" ? event.data : String(event.data));
			} catch {
				return;
			}
			if (typeof msg.id === "number") {
				const entry = this.pending.get(msg.id);
				if (!entry) return;
				this.pending.delete(msg.id);
				if (msg.error) entry.reject(new Error(`${msg.error.message}${msg.error.data ? `: ${msg.error.data}` : ""}`));
				else entry.resolve(msg.result);
				return;
			}
			if (typeof msg.method === "string") {
				for (const handler of this.listeners.get(msg.method) ?? []) {
					try {
						handler(msg.params ?? {});
					} catch {
						// listeners must not break the protocol pump
					}
				}
			}
		});
		this.ws.addEventListener("close", () => this.failAll(new Error("CDP connection closed")));
		this.ws.addEventListener("error", () => this.failAll(new Error("CDP connection error")));
	}

	static connect(wsUrl: string): Promise<CdpConnection> {
		const cached = CdpConnection.cache.get(wsUrl);
		if (cached) return cached;
		const promise = new Promise<CdpConnection>((resolve, reject) => {
			const ws = new WebSocket(wsUrl);
			const timer = setTimeout(() => {
				try {
					ws.close();
				} catch {}
				reject(new Error(`Timed out connecting to ${wsUrl}`));
			}, CDP_TIMEOUT_MS);
			ws.addEventListener("open", () => {
				clearTimeout(timer);
				resolve(new CdpConnection(ws));
			});
			ws.addEventListener("error", () => {
				clearTimeout(timer);
				reject(new Error(`Could not connect to ${wsUrl}`));
			});
		});
		CdpConnection.cache.set(wsUrl, promise);
		promise.catch(() => CdpConnection.cache.delete(wsUrl));
		return promise;
	}

	private failAll(error: Error): void {
		this.closed = true;
		for (const { reject } of this.pending.values()) reject(error);
		this.pending.clear();
		CdpConnection.cache.forEach((value, key) => {
			value.then((conn) => {
				if (conn === this) CdpConnection.cache.delete(key);
			}).catch(() => {});
		});
	}

	send<T = any>(method: string, params: Record<string, unknown> = {}, timeoutMs = CDP_TIMEOUT_MS): Promise<T> {
		if (this.closed) return Promise.reject(new Error("CDP connection closed"));
		const id = this.nextId++;
		return new Promise<T>((resolve, reject) => {
			const timer = setTimeout(() => {
				this.pending.delete(id);
				reject(new Error(`CDP ${method} timed out after ${timeoutMs}ms`));
			}, timeoutMs);
			this.pending.set(id, {
				resolve: (value) => {
					clearTimeout(timer);
					resolve(value as T);
				},
				reject: (error) => {
					clearTimeout(timer);
					reject(error);
				},
			});
			this.ws.send(JSON.stringify({ id, method, params }));
		});
	}

	on(method: string, handler: CdpEventHandler): () => void {
		let set = this.listeners.get(method);
		if (!set) {
			set = new Set();
			this.listeners.set(method, set);
		}
		set.add(handler);
		return () => set!.delete(handler);
	}

	close(): void {
		try {
			this.ws.close();
		} catch {}
		this.failAll(new Error("CDP connection closed"));
	}
}

interface TabInfo {
	id: string;
	title: string;
	url: string;
	type: string;
}

async function listTabs(): Promise<TabInfo[]> {
	const res = await fetch(`${BASE}/json/list`, { signal: AbortSignal.timeout(3000) });
	if (!res.ok) throw new Error(`Could not list tabs (HTTP ${res.status})`);
	const tabs = (await res.json()) as TabInfo[];
	return tabs.filter((tab) => tab.type === "page");
}

async function newTab(url: string): Promise<TabInfo> {
	const res = await fetch(`${BASE}/json/new?${encodeURIComponent(url)}`, {
		method: "PUT",
		signal: AbortSignal.timeout(10_000),
	});
	if (!res.ok) throw new Error(`Could not open a tab (HTTP ${res.status})`);
	return (await res.json()) as TabInfo;
}

/** Poll a tab until its document is parsed, or the deadline passes. */
async function waitForLoad(cdp: CdpConnection, timeoutMs = NAV_TIMEOUT_MS): Promise<void> {
	const deadline = Date.now() + timeoutMs;
	while (Date.now() < deadline) {
		try {
			const state = await cdp.send<{ result: { value: string } }>("Runtime.evaluate", {
				expression: "document.readyState",
				returnByValue: true,
			});
			const ready = state.result?.value;
			if (ready === "complete" || ready === "interactive") return;
		} catch {
			// the execution context is still being created
		}
		await sleep(200);
	}
}

function isIgnorableUrl(url: string): boolean {
	return url === "about:blank" || url.startsWith("chrome://") || url.startsWith("devtools://");
}

function defaultScreenshotPath(): Promise<string> {
	return mkdtemp(join(tmpdir(), "pi-chrome-")).then((dir) => join(dir, `screenshot-${Date.now()}.png`));
}

/** Open a tab, wait for it to finish navigating, focus it, and return its target. */
async function focusNewTab(url: string): Promise<Target> {
	const tab = await newTab(url);
	await fetch(`${BASE}/json/activate/${tab.id}`, { signal: AbortSignal.timeout(5000) }).catch(() => {});
	const cdp = await CdpConnection.connect(tab.webSocketDebuggerUrl);
	// `/json/new` may hand back the target before the navigation commits, which
	// leaves the page on about:blank. Enable Page and navigate explicitly.
	await cdp.send("Page.enable").catch(() => {});
	await cdp.send("Runtime.enable").catch(() => {});
	await cdp.send("Page.navigate", { url }).catch(() => {});
	await waitForLoad(cdp);
	return { tab, cdp };
}

/**
 * Resolve a working tab. With `newTabUrl` a fresh tab is opened; otherwise an
 * existing page tab is reused, preferring `tabId` and then the most recent
 * non-blank tab.
 */
async function openTarget(newTabUrl?: string, tabId?: string): Promise<Target> {
	if (newTabUrl !== undefined) return focusNewTab(newTabUrl);
	const tabs = await listTabs();
	let tab: TabInfo | undefined;
	if (tabId) {
		tab = tabs.find((candidate) => candidate.id === tabId);
		if (!tab) throw new Error(`No tab with id ${tabId}. Use browser_tabs to list tabs.`);
	} else {
		const pages = tabs.filter((candidate) => !isIgnorableUrl(candidate.url));
		tab = pages[pages.length - 1] ?? tabs[tabs.length - 1];
	}
	if (!tab) throw new Error("No page tab is open. Use browser_navigate to open one.");
	const cdp = await CdpConnection.connect(tab.webSocketDebuggerUrl);
	return { tab, cdp };
}

// ---------------------------------------------------------------------------
// in-page scripts
// ---------------------------------------------------------------------------

/** Extracts readable text plus a list of interactive elements with stable selectors. */
const SNAPSHOT_SCRIPT = `(() => {
	const MAX_ELEMENTS = 150;
	const MAX_TEXT = ${MAX_TEXT_CHARS};
	const visible = (el) => {
		const style = window.getComputedStyle(el);
		if (style.visibility === "hidden" || style.display === "none" || Number(style.opacity) === 0) return false;
		const rect = el.getBoundingClientRect();
		return rect.width > 0 && rect.height > 0;
	};
	const clean = (value, max) => (value || "").replace(/\\s+/g, " ").trim().slice(0, max);
	const label = (el) => clean(
		el.innerText ||
		el.getAttribute("aria-label") ||
		el.getAttribute("placeholder") ||
		el.getAttribute("title") ||
		el.value ||
		el.getAttribute("name") ||
		"",
		120,
	);
	const selector = (el) => {
		if (el.id && document.querySelectorAll("#" + CSS.escape(el.id)).length === 1) return "#" + CSS.escape(el.id);
		const parts = [];
		let node = el;
		while (node && node.nodeType === 1 && parts.length < 6) {
			let part = node.tagName.toLowerCase();
			if (node.id) { parts.unshift("#" + CSS.escape(node.id)); break; }
			const parent = node.parentElement;
			if (parent) {
				const sameTag = Array.from(parent.children).filter((child) => child.tagName === node.tagName);
				if (sameTag.length > 1) part += ":nth-of-type(" + (sameTag.indexOf(node) + 1) + ")";
			}
			parts.unshift(part);
			node = node.parentElement;
			if (node === document.body) { parts.unshift("body"); break; }
		}
		return parts.join(" > ");
	};
	const candidateSelector = 'a[href],button,input,select,textarea,[role="button"],[role="link"],[role="checkbox"],[role="tab"],[onclick],[contenteditable="true"],summary,label';
	const elements = [];
	const seen = new Set();
	for (const el of document.querySelectorAll(candidateSelector)) {
		if (elements.length >= MAX_ELEMENTS) break;
		if (!visible(el)) continue;
		const text = label(el);
		if (!text && !["input", "textarea", "select"].includes(el.tagName.toLowerCase())) continue;
		const sel = selector(el);
		if (seen.has(sel)) continue;
		seen.add(sel);
		const entry = { index: elements.length + 1, tag: el.tagName.toLowerCase(), selector: sel, text };
		if (el.tagName.toLowerCase() === "a") entry.href = el.href;
		if (["input", "textarea", "select"].includes(el.tagName.toLowerCase())) {
			entry.type = el.getAttribute("type") || el.tagName.toLowerCase();
			if (el.value && entry.type !== "password") entry.value = clean(el.value, 80);
		}
		if (el.disabled) entry.disabled = true;
		elements.push(entry);
	}
	let text = "";
	const main = document.querySelector("main, article, [role=main]") || document.body;
	if (main) {
		const clone = main.cloneNode(true);
		for (const junk of clone.querySelectorAll("script,style,noscript,svg,template")) junk.remove();
		text = (clone.innerText || "").replace(/\\n{3,}/g, "\\n\\n").trim();
	}
	const truncated = text.length > MAX_TEXT;
	return {
		url: location.href,
		title: document.title,
		text: truncated ? text.slice(0, MAX_TEXT) : text,
		textTruncated: truncated,
		elements,
	};
})()`;

const RESOLVE_SCRIPT = (selector: string, text: string) => `(() => {
	const explicit = ${JSON.stringify(selector)};
	const wanted = ${JSON.stringify(text.toLowerCase())};
	const visible = (el) => {
		const style = window.getComputedStyle(el);
		if (style.visibility === "hidden" || style.display === "none") return false;
		const rect = el.getBoundingClientRect();
		return rect.width > 0 && rect.height > 0;
	};
	if (explicit) {
		const el = document.querySelector(explicit);
		if (!el) return { error: "No element matches selector " + explicit };
		if (!visible(el)) return { error: "Element matches selector but is not visible: " + explicit };
		return { found: true };
	}
	if (!wanted) return { error: "Provide a selector or text." };
	const candidates = Array.from(document.querySelectorAll('a,button,input,select,textarea,[role="button"],[role="link"],[role="tab"],[onclick],summary,label'));
	const matches = candidates.filter((el) => visible(el) && ((el.innerText || el.value || el.getAttribute("aria-label") || el.getAttribute("placeholder") || el.getAttribute("title") || "").toLowerCase().includes(wanted)));
	if (matches.length === 0) return { error: "No visible element contains that text." };
	if (matches.length > 1) {
		const exact = matches.filter((el) => (el.innerText || el.value || "").trim().toLowerCase() === wanted);
		if (exact.length === 1) return { found: true };
		return { error: "Ambiguous: " + matches.length + " elements match. Use a CSS selector. Matches: " + matches.slice(0, 8).map((el) => JSON.stringify((el.innerText || el.value || "").trim().slice(0, 60))).join(", ") };
	}
	return { found: true };
})()`;

function clickScript(opts: { selector?: string; text?: string; x?: number; y?: number }): string {
	if (opts.x !== undefined && opts.y !== undefined) {
		return `(() => {
	const el = document.elementFromPoint(${opts.x}, ${opts.y});
	if (!el) return { error: "Nothing at those coordinates." };
	el.click();
	return { clicked: true, tag: el.tagName.toLowerCase(), text: (el.innerText || "").trim().slice(0, 80) };
})()`;
	}
	return `(() => {
	const explicit = ${JSON.stringify(opts.selector ?? "")};
	const wanted = ${JSON.stringify((opts.text ?? "").toLowerCase())};
	const visible = (el) => {
		const style = window.getComputedStyle(el);
		if (style.visibility === "hidden" || style.display === "none") return false;
		const rect = el.getBoundingClientRect();
		return rect.width > 0 && rect.height > 0;
	};
	let el = null;
	if (explicit) {
		el = document.querySelector(explicit);
		if (!el) return { error: "No element matches selector " + explicit };
	} else if (wanted) {
		const candidates = Array.from(document.querySelectorAll('a,button,input,select,textarea,[role="button"],[role="link"],[role="tab"],[onclick],summary,label'));
		const matches = candidates.filter((node) => visible(node) && ((node.innerText || node.value || node.getAttribute("aria-label") || node.getAttribute("placeholder") || node.getAttribute("title") || "").toLowerCase().includes(wanted)));
		const exact = matches.filter((node) => (node.innerText || node.value || "").trim().toLowerCase() === wanted);
		el = exact.length === 1 ? exact[0] : matches.length === 1 ? matches[0] : null;
		if (!el) {
			if (matches.length === 0) return { error: "No visible element contains that text." };
			return { error: "Ambiguous: " + matches.length + " elements match. Use a CSS selector." };
		}
	} else {
		return { error: "Provide a selector, text, or x/y coordinates." };
	}
	el.scrollIntoView({ block: "center", inline: "center" });
	el.focus({ preventScroll: true });
	const rect = el.getBoundingClientRect();
	const x = rect.left + rect.width / 2;
	const y = rect.top + rect.height / 2;
	for (const type of ["pointerdown", "mousedown", "pointerup", "mouseup", "click"]) {
		el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
	}
	if (typeof el.click === "function") el.click();
	return { clicked: true, tag: el.tagName.toLowerCase(), text: (el.innerText || el.value || "").trim().slice(0, 80), href: el.href || null };
})()`;
}

function typeScript(opts: { selector?: string; text?: string; value: string; submit: boolean }): string {
	return `(() => {
	const explicit = ${JSON.stringify(opts.selector ?? "")};
	const wanted = ${JSON.stringify((opts.text ?? "").toLowerCase())};
	const value = ${JSON.stringify(opts.value)};
	const submit = ${opts.submit ? "true" : "false"};
	let el = null;
	if (explicit) {
		el = document.querySelector(explicit);
		if (!el) return { error: "No element matches selector " + explicit };
	} else if (wanted) {
		const fields = Array.from(document.querySelectorAll("input,textarea,select,[contenteditable=true]"));
		el = fields.find((node) => ((node.getAttribute("aria-label") || node.getAttribute("placeholder") || node.getAttribute("name") || node.id || "").toLowerCase().includes(wanted))) || null;
		if (!el) return { error: "No input field matching that text." };
	} else {
		el = document.querySelector("input:not([type=hidden]),textarea,[contenteditable=true]");
		if (!el) return { error: "No input field on the page." };
	}
	el.focus();
	if (el.isContentEditable) {
		el.textContent = value;
	} else {
		const proto = el instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
		const setter = Object.getOwnPropertyDescriptor(proto, "value");
		if (setter && setter.set) setter.set.call(el, value);
		else el.value = value;
	}
	el.dispatchEvent(new Event("input", { bubbles: true }));
	el.dispatchEvent(new Event("change", { bubbles: true }));
	if (submit) {
		if (el.form && typeof el.form.requestSubmit === "function") el.form.requestSubmit();
		else {
			for (const type of ["keydown", "keypress", "keyup"]) {
				el.dispatchEvent(new KeyboardEvent(type, { key: "Enter", code: "Enter", keyCode: 13, which: 13, bubbles: true }));
			}
		}
	}
	return { typed: true, value: el.value !== undefined ? String(el.value).slice(0, 80) : value.slice(0, 80), submitted: submit };
})()`;
}

// ---------------------------------------------------------------------------
// rendering helpers
// ---------------------------------------------------------------------------

function textResult(text: string, details: unknown) {
	return { content: [{ type: "text" as const, text }], details };
}

function formatSnapshot(snapshot: {
	url: string;
	title: string;
	text: string;
	textTruncated: boolean;
	elements: Array<{ index: number; tag: string; selector: string; text: string; href?: string; type?: string; disabled?: boolean }>;
}): string {
	const lines = [`URL: ${snapshot.url}`, `Title: ${snapshot.title}`, ""];
	if (snapshot.elements.length > 0) {
		lines.push(`Interactive elements (${snapshot.elements.length}):`);
		for (const el of snapshot.elements) {
			const flags = [el.type ? `type=${el.type}` : null, el.disabled ? "disabled" : null].filter(Boolean).join(" ");
			lines.push(`[${el.index}] <${el.tag}${flags ? ` ${flags}` : ""}> ${JSON.stringify(el.text)} selector=${el.selector}${el.href ? ` href=${el.href}` : ""}`);
		}
		lines.push("");
	} else {
		lines.push("Interactive elements: none found", "");
	}
	lines.push("Page text:");
	lines.push(snapshot.text || "(empty)");
	if (snapshot.textTruncated) lines.push(`\n[text truncated to ${MAX_TEXT_CHARS} characters]`);
	return lines.join("\n");
}

function formatTabs(tabs: TabInfo[], activeId?: string): string {
	if (tabs.length === 0) return "No page tabs are open.";
	return tabs
		.map((tab, i) => `${i + 1}. ${tab.id === activeId ? "* " : ""}${tab.title || "(untitled)"}\n   ${tab.url}\n   id=${tab.id}`)
		.join("\n");
}

// ---------------------------------------------------------------------------
// extension
// ---------------------------------------------------------------------------

export default function (pi: ExtensionAPI) {
	let activeTabId: string | undefined;

	async function prepare(): Promise<void> {
		if (existsSync(CHROME_BIN) || spawnSync("bash", ["-lc", `command -v ${CHROME_BIN}`], { stdio: "ignore" }).status === 0) {
			await ensureBrowser();
			return;
		}
		throw new Error(`${CHROME_BIN} was not found on PATH. Set PI_CHROME_BIN to a Chrome/Chromium binary.`);
	}

	pi.registerCommand("chrome", {
		description: "Manage the agent browser (usage: /chrome [start|stop|status])",
		handler: async (args, ctx) => {
			const action = (args ?? "").trim().toLowerCase();
			try {
						if (action === "stop") {
					await killManagedBrowser();
					activeTabId = undefined;
					ctx.ui.notify("Agent browser stopped.", "info");
					return;
				}
				if (action === "status" || action === "") {
					const version = await browserVersion();
					if (!version) {
						ctx.ui.notify(`Agent browser is not running (${BASE}). Run /chrome to start it.`, "info");
						return;
					}
					const tabs = await listTabs().catch(() => []);
					ctx.ui.notify(
						`${version.Browser}\nCDP: ${BASE}\ntmux: ${hasTmux() ? TMUX_SESSION : "unavailable"}\nprofile: ${PROFILE_DIR}\ntabs: ${tabs.length}`,
						"info",
					);
					return;
				}
				const info = await ensureBrowser(action === "restart");
				ctx.ui.notify(`Agent browser ready (${info.version}) via ${info.launched}. CDP: ${BASE}`, "info");
			} catch (error) {
				ctx.ui.notify(`Agent browser error: ${error instanceof Error ? error.message : String(error)}`, "error");
			}
		},
	});

	pi.registerTool({
		name: "browser_navigate",
		label: "Browser Navigate",
		description:
			"Open a URL in a new tab of the agent's own Chrome instance (started automatically in a detached tmux session) and return the page's readable text plus interactive elements.",
		parameters: Type.Object({
			url: Type.String({ description: "Absolute URL to open" }),
			include_snapshot: Type.Optional(
				Type.Boolean({ description: "Also return interactive elements and page text (default: true)" }),
			),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const { tab, cdp } = await focusNewTab(params.url);
			activeTabId = tab.id;
			await cdp.send("Page.enable").catch(() => {});
			await cdp.send("Runtime.enable").catch(() => {});
			await waitForLoad(cdp);
			if (params.include_snapshot === false) {
				const info = await cdp
					.send<{ result: { value: { url: string; title: string } } }>("Runtime.evaluate", {
						expression: "({ url: location.href, title: document.title })",
						returnByValue: true,
					})
					.catch(() => null);
				const value = info?.result?.value;
				return textResult(`Opened tab ${tab.id}\nURL: ${value?.url ?? params.url}\nTitle: ${value?.title ?? ""}`, {
					tabId: tab.id,
					url: value?.url ?? params.url,
				});
			}
			const snapshot = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: SNAPSHOT_SCRIPT,
				returnByValue: true,
				awaitPromise: true,
			});
			const value = snapshot.result?.value;
			return textResult(formatSnapshot(value), { tabId: tab.id, ...value });
		},
	});

	pi.registerTool({
		name: "browser_snapshot",
		label: "Browser Snapshot",
		description:
			"Return the readable text and interactive elements of the current browser tab, so you can find selectors or link text to act on.",
		parameters: Type.Object({
			tab_id: Type.Optional(Type.String({ description: "Tab id from browser_tabs (default: most recent tab)" })),
			max_elements: Type.Optional(Type.Number({ description: "Number of interactive elements to list (default: 100)" })),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const { tab, cdp } = await openTarget(undefined, params.tab_id ?? activeTabId);
			activeTabId = tab.id;
			const snapshot = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: SNAPSHOT_SCRIPT,
				returnByValue: true,
			});
			const value = snapshot.result?.value;
			if (params.max_elements && value?.elements) {
				value.elements = value.elements.slice(0, Math.max(1, params.max_elements));
			}
			return textResult(formatSnapshot(value), { tabId: tab.id, ...value });
		},
	});

	pi.registerTool({
		name: "browser_click",
		label: "Browser Click",
		description:
			"Click an element in the current browser tab by CSS selector, by visible text, or by viewport coordinates. Returns the updated page snapshot.",
		parameters: Type.Object({
			selector: Type.Optional(Type.String({ description: "CSS selector of the element to click" })),
			text: Type.Optional(Type.String({ description: "Visible text (or aria-label/placeholder) of the element" })),
			x: Type.Optional(Type.Number({ description: "Viewport x coordinate" })),
			y: Type.Optional(Type.Number({ description: "Viewport y coordinate" })),
			tab_id: Type.Optional(Type.String({ description: "Tab id from browser_tabs (default: most recent tab)" })),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const { tab, cdp } = await openTarget(undefined, params.tab_id ?? activeTabId);
			activeTabId = tab.id;
			const result = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: clickScript({ selector: params.selector, text: params.text, x: params.x, y: params.y }),
				returnByValue: true,
			});
			const value = result.result?.value;
			if (value?.error) throw new Error(value.error);
			await sleep(750);
			const snapshot = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: SNAPSHOT_SCRIPT,
				returnByValue: true,
			});
			return textResult(`Clicked ${value?.tag ?? "element"} ${JSON.stringify(value?.text ?? "")}\n\n${formatSnapshot(snapshot.result?.value)}`, {
				tabId: tab.id,
				clicked: value,
				...snapshot.result?.value,
			});
		},
	});

	pi.registerTool({
		name: "browser_type",
		label: "Browser Type",
		description:
			"Type text into a field in the current browser tab (by CSS selector or by placeholder/label text) and optionally submit it.",
		parameters: Type.Object({
			value: Type.String({ description: "Text to type" }),
			selector: Type.Optional(Type.String({ description: "CSS selector of the field" })),
			text: Type.Optional(Type.String({ description: "Placeholder, aria-label, name or id of the field" })),
			submit: Type.Optional(Type.Boolean({ description: "Submit the form / press Enter after typing (default: false)" })),
			tab_id: Type.Optional(Type.String({ description: "Tab id from browser_tabs (default: most recent tab)" })),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const { tab, cdp } = await openTarget(undefined, params.tab_id ?? activeTabId);
			activeTabId = tab.id;
			const result = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: typeScript({
					selector: params.selector,
					text: params.text,
					value: params.value,
					submit: params.submit ?? false,
				}),
				returnByValue: true,
			});
			const value = result.result?.value;
			if (value?.error) throw new Error(value.error);
			if (params.submit) await sleep(1500);
			const snapshot = await cdp.send<{ result: { value: any } }>("Runtime.evaluate", {
				expression: SNAPSHOT_SCRIPT,
				returnByValue: true,
			});
			return textResult(
				`Typed ${JSON.stringify(value?.value ?? "")}${value?.submitted ? " and submitted" : ""}\n\n${formatSnapshot(snapshot.result?.value)}`,
				{ tabId: tab.id, typed: value, ...snapshot.result?.value },
			);
		},
	});

	pi.registerTool({
		name: "browser_eval",
		label: "Browser Eval",
		description:
			"Evaluate a JavaScript expression in the current browser tab and return its value as JSON. Use for reading data, waiting, or driving pages without a usable selector.",
		parameters: Type.Object({
			expression: Type.String({ description: "JavaScript expression to evaluate in the page" }),
			await_promise: Type.Optional(Type.Boolean({ description: "Await the result if it is a promise (default: true)" })),
			tab_id: Type.Optional(Type.String({ description: "Tab id from browser_tabs (default: most recent tab)" })),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const { tab, cdp } = await openTarget(undefined, params.tab_id ?? activeTabId);
			activeTabId = tab.id;
			const result = await cdp.send<{ result: any; exceptionDetails?: any }>("Runtime.evaluate", {
				expression: params.expression,
				returnByValue: true,
				awaitPromise: params.await_promise !== false,
				userGesture: true,
			});
			if (result.exceptionDetails) {
				const description =
					result.exceptionDetails.exception?.description ?? result.exceptionDetails.text ?? "evaluation failed";
				throw new Error(description);
			}
			const json = JSON.stringify(result.result?.value, null, 2);
			return textResult(json === undefined ? "undefined" : json, { tabId: tab.id, value: result.result?.value });
		},
	});

	pi.registerTool({
		name: "browser_screenshot",
		label: "Browser Screenshot",
		description: "Capture a PNG screenshot of the current browser tab and save it to a file.",
		parameters: Type.Object({
			path: Type.Optional(Type.String({ description: "File path to write (default: a temp file)" })),
			full_page: Type.Optional(Type.Boolean({ description: "Capture the full scrollable page (default: false)" })),
			tab_id: Type.Optional(Type.String({ description: "Tab id from browser_tabs (default: most recent tab)" })),
		}),
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			await prepare();
			const { tab, cdp } = await openTarget(undefined, params.tab_id ?? activeTabId);
			activeTabId = tab.id;
			let clip: Record<string, number> | undefined;
			if (params.full_page) {
				const metrics = await cdp.send<{ contentSize: { width: number; height: number } }>("Page.getLayoutMetrics");
				clip = {
					x: 0,
					y: 0,
					width: Math.ceil(metrics.contentSize.width),
					height: Math.ceil(metrics.contentSize.height),
					scale: 1,
				};
			}
			const shot = await cdp.send<{ data: string }>("Page.captureScreenshot", {
				format: "png",
				captureBeyondViewport: params.full_page ?? false,
				...(clip ? { clip } : {}),
			});
			const target = params.path ?? (await defaultScreenshotPath());
			await writeFile(target, Buffer.from(shot.data, "base64"));
			return textResult(`Screenshot saved to ${target}`, { tabId: tab.id, path: target });
		},
	});

	pi.registerTool({
		name: "browser_tabs",
		label: "Browser Tabs",
		description: "List the open browser tabs, select one as the active tab, or close one.",
		parameters: Type.Object({
			action: Type.Optional(
				Type.String({ description: "list (default), select, or close", enum: ["list", "select", "close"] }),
			),
			tab_id: Type.Optional(Type.String({ description: "Tab id for select or close" })),
		}),
		async execute(_toolCallId, params) {
			await prepare();
			const action = params.action ?? "list";
			if (action === "select" || action === "close") {
				if (!params.tab_id) throw new Error(`tab_id is required for ${action}`);
				const res = await fetch(`${BASE}/json/${action === "close" ? "close" : "activate"}/${params.tab_id}`, {
					signal: AbortSignal.timeout(5000),
				});
				if (!res.ok) throw new Error(`Could not ${action} tab ${params.tab_id} (HTTP ${res.status})`);
				if (action === "close" && activeTabId === params.tab_id) activeTabId = undefined;
				if (action === "select") activeTabId = params.tab_id;
			}
			const tabs = await listTabs();
			return textResult(formatTabs(tabs, activeTabId), { tabs, activeTabId });
		},
	});

	pi.registerTool({
		name: "browser_close",
		label: "Browser Close",
		description:
			"Stop the agent's managed Chrome instance. The browser is left running by default after a session ends; call this only when the user asks to close the browser.",
		parameters: Type.Object({}),
		async execute() {
			await killManagedBrowser();
			activeTabId = undefined;
			return textResult(`Agent browser stopped (tmux: ${TMUX_SESSION}, profile: ${PROFILE_DIR}).`, { stopped: true });
		},
	});
}
