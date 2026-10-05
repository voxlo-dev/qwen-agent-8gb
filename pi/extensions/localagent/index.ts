// Runs the localagent workflow (./workflow, copied from pi/localagent-workflow) on pi.
// `pi --localagent` makes the session its orchestrator: the orchestrator prompt, which is the whole
// protocol, is appended to the system prompt (with a line saying whether a human is reachable, so
// the plan gate is not the model's guess), and the `dispatch` tool starts one localagent-* agent as
// a separate `pi -p` process, one at a time, and appends its result to localagent/LOG.md, the run's
// ledger. Without the flag it does nothing.
// Two limits come from the environment, set by bin/qwen-pi from config.env: LOCALAGENT_AGENT_MODEL,
// the models.json entry the agents run on (a smaller thinking budget than the orchestrator), and
// LOCALAGENT_MAX_TURNS, a backstop after which a runaway dispatch is killed and reported as BLOCKED.
// After a DONE the tool runs the unit's test command itself, so the gate is a fact in the result,
// not a model turn; it lists what the dispatch changed. Nothing is put back: the next dispatch
// starts from the tree as it is, with a fresh context. An agent's first green run after a red one
// ends its dispatch as DONE.
// Rationale: docs/localagent.md.
import { spawn, spawnSync } from "node:child_process";
import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { StringEnum } from "@earendil-works/pi-ai";
import { type ExtensionAPI, parseFrontmatter } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const here = path.dirname(fileURLToPath(import.meta.url));
const workflow = path.join(here, "workflow");
const STATUS = /^(DONE|ESCALATE|BLOCKED|PASS|FIXES_REQUIRED|NO_SURFACE)\b/;
const MAX_TURNS = Math.max(1, Number(process.env.LOCALAGENT_MAX_TURNS) || 30);
const AGENT_MODEL = process.env.LOCALAGENT_AGENT_MODEL || "";

interface Agent {
	name: string;
	primary: boolean;
	prompt: string;
}

function loadAgents(): Agent[] {
	const dir = path.join(workflow, "agents");
	return fs
		.readdirSync(dir)
		.filter((f) => f.endsWith(".md"))
		.sort()
		.map((f) => {
			const { frontmatter: fm, body } = parseFrontmatter<Record<string, any>>(fs.readFileSync(path.join(dir, f), "utf8"));
			return {
				name: fm.name ?? f.slice(0, -3),
				primary: fm.mode === "primary",
				prompt: body,
			};
		});
}

// pi's own entry point, so a child runs the same pinned version (as in pi's subagent example).
function piInvocation(args: string[]): [string, string[]] {
	const script = process.argv[1];
	if (script && fs.existsSync(script)) return [process.execPath, [script, ...args]];
	return ["pi", args];
}

function lastText(message: any): string {
	const parts = Array.isArray(message?.content) ? message.content : [];
	return parts
		.filter((p: any) => p.type === "text")
		.map((p: any) => p.text)
		.join("\n")
		.trim();
}

// The orchestrator gets the agent's status line, Markdown stripped (`**DONE**` arrived as `DONE**`).
// A reply that names no status says so rather than passing its last line off as one.
function statusLine(text: string): string {
	const lines = text.split("\n").map((l) => l.replace(/[`*]/g, "").trim()).filter(Boolean);
	const status = [...lines].reverse().find((l) => STATUS.test(l));
	return status ?? (lines.length ? `NO STATUS: ${lines.slice(-3).join(" | ").slice(0, 300)}` : "");
}

// The work tree as a git tree object, written through a private copy of the index, so the user's
// index, HEAD and history stay as they are (the blobs land in the object store, as `git stash`'s
// would). Null outside a git work tree.
function snapshot(cwd: string): string | null {
	const real = spawnSync("git", ["rev-parse", "--git-path", "index"], { cwd, encoding: "utf8" });
	if (real.status !== 0) return null;
	const index = path.join(os.tmpdir(), `localagent-${process.pid}.index`);
	const src = path.resolve(cwd, real.stdout.trim());
	if (fs.existsSync(src)) fs.copyFileSync(src, index);
	else fs.rmSync(index, { force: true });
	const env = { ...process.env, GIT_INDEX_FILE: index };
	const add = spawnSync("git", ["add", "-A", "--", "."], { cwd, env, encoding: "utf8" });
	const tree = add.status === 0 ? spawnSync("git", ["write-tree"], { cwd, env, encoding: "utf8" }) : null;
	fs.rmSync(index, { force: true });
	return tree?.status === 0 ? tree.stdout.trim() : null;
}

export default function (pi: ExtensionAPI) {
	pi.registerFlag("localagent", {
		description: "Run this session as the localagent-workflow orchestrator",
		type: "boolean",
		default: false,
	});

	let agents: Agent[] = [];
	let queue: Promise<unknown> = Promise.resolve();

	pi.on("session_start", async (_event, ctx) => {
		if (!pi.getFlag("localagent")) return;
		agents = loadAgents();
		const subagents = agents.filter((a) => !a.primary).map((a) => a.name);
		if (!agents.some((a) => a.primary) || !subagents.length) {
			ctx.ui.notify(`localagent: no orchestrator or no agents in ${workflow}/agents`, "error");
			return;
		}

		ctx.ui.notify(
			`localagent is frozen and not recommended: on this model it fails real tasks that qwen-pi without ` +
				`--localagent finishes. Agents: ${AGENT_MODEL || "the session model"}, at most ${MAX_TURNS} turns each. ` +
				`See docs/localagent.md#status.`,
			"warning",
		);

		pi.registerTool({
			name: "dispatch",
			label: "Dispatch",
			description:
				"Run one localagent-* agent on a brief and wait for its one-line result (DONE, ESCALATE, BLOCKED, ...). " +
				"The agent starts with an empty context: the brief must carry the absolute working directory, the " +
				"commands, the task, and the paths of its inputs. Agents run one at a time; a runaway is cut off " +
				"(BLOCKED). With `test`, the command runs after a DONE and its verdict is appended " +
				"to the result, then the files this dispatch changed. A failed dispatch's files stay where it left them.",
			promptSnippet: "Run one localagent-* agent on a brief and return its status line",
			parameters: Type.Object({
				agent: StringEnum(subagents as [string, ...string[]], { description: "Agent name" }),
				brief: Type.String({ description: "Working directory, commands, task, input paths" }),
				unit: Type.Optional(Type.String({ description: "The unit this dispatch works on, e.g. U2; named in the run log" })),
				test: Type.Optional(Type.String({ description: "Test command to run in the working directory after a DONE" })),
			}),
			async execute(_id, params, signal, onUpdate, ctx) {
				const run = queue.then(() => dispatch(params.agent, params.brief, params.unit, params.test, signal, onUpdate, ctx));
				queue = run.catch(() => {});
				return run;
			},
		});
	});

	// The plan gate needs to know whether anyone can answer it; pi knows, the model does not.
	pi.on("before_agent_start", async (event, ctx) => {
		const orchestrator = agents.find((a) => a.primary);
		if (!orchestrator) return;
		const gate = ctx.hasUI
			? "A human is at this session: the plan gate is binding. Show the plan and stop until it is approved."
			: "No human is reachable (headless): mark the plan auto-approved in PLAN.md and continue.";
		const prompt = orchestrator.prompt.replaceAll("{{templates}}", path.join(workflow, "templates"));
		return { systemPrompt: `${event.systemPrompt}\n\n${prompt}\n\n## Session\n\n${gate}` };
	});

	async function dispatch(name: string, brief: string, unit: string | undefined, test: string | undefined, signal: AbortSignal | undefined, onUpdate: any, ctx: any) {
		const agent = agents.find((a) => a.name === name && !a.primary);
		if (!agent) throw new Error(`BLOCKED unknown agent ${name}`);

		// Nothing the orchestrator session loaded reaches the child: no extensions (so no nested
		// dispatch), no skills, no AGENTS.md. The brief is its whole context.
		const args = ["--mode", "json", "-p", "--no-extensions", "--no-skills", "--no-prompt-templates", "--no-context-files"];
		if (AGENT_MODEL) args.push("--model", AGENT_MODEL);
		const sessionFile = ctx.sessionManager.getSessionFile();
		const sessionDir = sessionFile ? path.join(path.dirname(sessionFile), "dispatch", ctx.sessionManager.getSessionId()) : "";
		if (sessionDir) args.push("--session-dir", sessionDir);
		else args.push("--no-session");
		args.push("--append-system-prompt", agent.prompt, "--", brief);

		const before = snapshot(ctx.cwd);
		const started = Date.now();
		let turns = 0;
		let final: any;
		let stderr = "";
		let cutOff = false;
		// The test gate inside the dispatch. Whenever the agent runs a command containing the test
		// command, the child is paused (SIGSTOP) and the harness runs the exact command itself, so a
		// pipe, a subset or a different stack's exit convention does not decide. Red is remembered;
		// green after a red ends the dispatch: the tests were written before the code, so that is the
		// agent's own "done". Twice in T-019 a worker was green and spent its last turns on checks
		// nobody asked for until the backstop cut it off, and the unit was thrown away.
		const testCmd = test ? test.replace(/\s+/g, " ").trim() : "";
		const commands = new Map<string, string>();
		let seenRed = false;
		let greenEnd = false;
		// What the agent is doing, as far as its event stream shows it: the orchestrator only ever
		// gets the status line back, so this is the one live view of a dispatch. The full one is
		// the child's session JSONL - see runs/watch-dispatch.py.
		let usage = "";
		let said = "";
		const trim = (s: string, n: number) => (s.length > n ? `${s.slice(0, n)}…` : s);
		const progress = (what: string) =>
			onUpdate?.({
				content: [{ type: "text", text: [`${name} · turn ${turns}${usage} · ${what}`, said].filter(Boolean).join("\n") }],
				details: {},
			});

		const code = await new Promise<number>((resolve) => {
			const [cmd, argv] = piInvocation(args);
			const proc = spawn(cmd, argv, { cwd: ctx.cwd, stdio: ["ignore", "pipe", "pipe"] });
			let buffer = "";
			const onLine = (line: string) => {
				let event: any;
				try {
					event = JSON.parse(line);
				} catch {
					return;
				}
				if (event.type === "tool_execution_start") {
					const a = event.args ?? {};
					if (event.toolName === "bash" && typeof a.command === "string") commands.set(event.toolCallId, a.command);
					progress(`${event.toolName} ${trim(String(a.path ?? a.command ?? JSON.stringify(a)).replace(/\s+/g, " "), 300)}`);
				} else if (event.type === "tool_execution_end" && testCmd && !greenEnd && !cutOff) {
					const command = commands.get(event.toolCallId);
					commands.delete(event.toolCallId);
					if (command && command.replace(/\s+/g, " ").includes(testCmd)) gate();
				} else if (event.type === "message_end" && event.message?.role === "assistant") {
					turns++;
					final = event.message;
					const u = event.message.usage ?? {};
					usage = u.totalTokens ? ` · ${u.output ?? 0} out · ${u.totalTokens} ctx` : "";
					// Its own words beat "thinking": the last line of whatever it just said or thought.
					const parts = Array.isArray(event.message.content) ? event.message.content : [];
					const spoke = parts
						.map((p: any) => (p.type === "text" ? p.text : p.type === "thinking" ? p.thinking : ""))
						.filter(Boolean)
						.join("\n")
						.trim();
					said = spoke ? trim(spoke.split("\n").filter(Boolean).at(-1) ?? "", 300) : "";
					progress("thinking");
					// A backstop, not a rule: no agent has ever stopped itself, and none is told the number.
					// A cut-off dispatch is BLOCKED even when the suite is green: in the T-019 Tron run
					// "green" was `node --test` finding no test at all, and a result line naming the turn
					// count sent the orchestrator to its split rule twice.
					if (turns >= MAX_TURNS && final.stopReason !== "stop") {
						cutOff = true;
						kill();
					}
				}
			};
			proc.stdout.on("data", (d) => {
				buffer += d.toString();
				const lines = buffer.split("\n");
				buffer = lines.pop() ?? "";
				lines.forEach(onLine);
			});
			proc.stderr.on("data", (d) => (stderr += d.toString()));
			proc.on("close", (c) => {
				if (buffer.trim()) onLine(buffer);
				resolve(c ?? 1);
			});
			proc.on("error", (e) => {
				stderr += String(e);
				resolve(1);
			});
			const kill = () => {
				proc.kill("SIGCONT");
				proc.kill("SIGTERM");
				setTimeout(() => proc.exitCode === null && proc.kill("SIGKILL"), 5000).unref();
			};
			// Paused while the harness tests, so the tree it judges is the one the agent just ran.
			let gating = Promise.resolve();
			const gate = () => {
				gating = gating.then(async () => {
					if (greenEnd || cutOff || proc.exitCode !== null) return;
					proc.kill("SIGSTOP");
					const green = await passes(ctx.cwd, test!);
					if (!green) seenRed = true;
					else if (seenRed && !greenEnd) {
						greenEnd = true;
						progress("tests green after red: ending the dispatch");
						kill();
						return;
					}
					proc.kill("SIGCONT");
				});
			};
			if (signal?.aborted) kill();
			else signal?.addEventListener("abort", kill, { once: true });
		});

		if (signal?.aborted) throw new Error(`BLOCKED ${name} aborted`);
		// A dispatch the harness ended is a tool error; one the agent ended is its status line.
		const stop = final?.stopReason;
		let line: string;
		let error = true;
		if (greenEnd) {
			line = `DONE ${name} was ended by the harness at its first green test run after a red one`;
			error = false;
		} else if (cutOff) line = `BLOCKED ${name} was cut off before it finished; its files are in place. Log: ${sessionDir || "(no session)"}`;
		else if (code !== 0 || !final || (stop && stop !== "stop")) {
			const why = final?.errorMessage ?? (stop && stop !== "stop" ? `stopped on ${stop}` : stderr.trim().slice(-500) || `exit ${code}`);
			line = `BLOCKED ${name} did not finish: ${why}`;
		} else {
			line = statusLine(lastText(final)) || `BLOCKED ${name} returned no status line`;
			error = false;
		}
		// Taken before the test run, whose own output (__pycache__, coverage) is not the agent's work.
		const after = before ? snapshot(ctx.cwd) : null;
		if (test && /^(DONE|NO STATUS)\b/.test(line)) line += tests(ctx.cwd, test);
		line += changes(ctx.cwd, before, after);
		line += ` · ${turns} turns, ${Math.round((Date.now() - started) / 60_000)} min`;
		log(ctx.cwd, `${unit ? `${unit} ` : ""}${name}`, line);
		if (error) throw new Error(line);
		return { content: [{ type: "text", text: line }], details: { turns } };
	}

	// The run's ledger, written here so the orchestrator does not have to: keeping STATE.md by hand
	// took 10 to 18 of its 34 turns in each T-019 and Tron session, five of them failed edits. It
	// is what the orchestrator reads after a compaction. Only once the run has a localagent/ dir.
	function log(cwd: string, who: string, line: string) {
		const dir = path.join(cwd, "localagent");
		if (!fs.existsSync(dir)) return;
		const file = path.join(dir, "LOG.md");
		const head = fs.existsSync(file) ? "" : "# Run log\n\nOne line per dispatch, appended by `dispatch`: the result as the orchestrator got it.\n\n";
		const time = new Date().toTimeString().slice(0, 5);
		fs.appendFileSync(file, `${head}- ${time} ${who} · ${line.replace(/\s*\n\s*/g, " ")}\n`);
	}

	// The test command's verdict alone, without blocking the session while it runs.
	function passes(cwd: string, test: string): Promise<boolean> {
		return new Promise((resolve) => {
			const p = spawn("bash", ["-lc", test], { cwd, stdio: "ignore" });
			const timer = setTimeout(() => p.kill("SIGKILL"), 300_000);
			p.on("close", (c) => {
				clearTimeout(timer);
				resolve(c === 0);
			});
			p.on("error", () => {
				clearTimeout(timer);
				resolve(false);
			});
		});
	}

	// The objective gate after a DONE: the test command's verdict, a fact the orchestrator used to
	// spend eight turns establishing.
	function tests(cwd: string, test: string): string {
		const r = spawnSync("bash", ["-lc", test], { cwd, encoding: "utf8", timeout: 300_000 });
		const tail = `${r.stdout ?? ""}${r.stderr ?? ""}`.trim().split("\n").slice(-3).join(" | ").slice(0, 300);
		return r.status === 0 ? " · tests: green" : ` · tests: RED (exit ${r.status ?? "timeout"}): ${tail}`;
	}

	// What this dispatch changed, against the snapshot taken before it, so a later dispatch does not
	// inherit the credit: in T-019 a third U2 attempt came back DONE green in 34 seconds without
	// writing a file, on what two cut-off attempts had left on disk. Nothing is put back any more. A
	// revert threw a green unit away and, in the Tron run, deleted half of node_modules under a
	// scaffold whose install the backstop had cut off; the next agent sees the tree fresh instead.
	function changes(cwd: string, before: string | null, after: string | null): string {
		if (!before || !after) return "";
		const d = spawnSync("git", ["diff", "-z", "--name-only", "--no-renames", "--relative", before, after], { cwd, encoding: "utf8" });
		if (d.status !== 0) return "";
		const files = d.stdout.split("\0").filter(Boolean);
		return ` · changed: ${files.length ? files.slice(0, 20).join(" ") : "nothing"}${files.length > 20 ? " …" : ""}`;
	}
}
