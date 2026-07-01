# CrewAI Text Tool-Calling Research

Source reviewed: `crewAIInc/crewAI` at commit `e8dced8`, committed
`2026-06-29T14:56:13-03:00`, cloned under
`/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/crewai`.

## Summary

CrewAI supports two tool paths:

- native provider tool calling when the LLM advertises function/tool support;
- text ReAct-style tool calling when native tool calling is unavailable.

The text path is deliberately prompt-heavy and parser-heavy. It is a fallback for
models/providers that cannot return structured tool calls. For this package,
CrewAI is useful as evidence for a robust fallback prompt format, not as evidence
to prefer prompt-parsed tools over native FoundationModels tool capture.

## Prompt Structure

CrewAI builds prompts from translation slices in
`lib/crewai/src/crewai/translations/en.json`.

The agent identity slice is:

```text
You are {role}. {backstory}
Your personal goal is: {goal}
```

When tools exist and native tool calling is not used, CrewAI adds a tool slice:

```text
You ONLY have access to the following tools, and should NEVER make up tools that
are not listed here:

{tools}

IMPORTANT: Use the following format in your response:

Thought: you should always think about what to do
Action: the action to take, only one name of [{tool_names}], just the name,
exactly as it's written.
Action Input: the input to the action, just a simple JSON object, enclosed in
curly braces, using " to wrap keys and values.
Observation: the result of the action

Once all necessary information is gathered, return:

Thought: I now know the final answer
Final Answer: the final answer to the original input question
```

The task slice appends:

```text
Current Task: {input}

Begin! This is VERY important to you, use the tools available and give your best
Final Answer, your job depends on it!

Thought:
```

Prompt assembly lives in `lib/crewai/src/crewai/utilities/prompts.py`:

- Always starts with `role_playing`.
- Adds `tools` only when `has_tools` and `use_native_tool_calling == false`.
- Uses `native_task` instead of text tool instructions for native tool calling.
- Replaces `{role}`, `{goal}`, and `{backstory}` from the agent.

## Tool List Format

CrewAI renders tools as plain text through `render_text_description_and_args` in
`lib/crewai/src/crewai/utilities/agent_utils.py`:

```text
<tool description>, args: <JSON schema properties>
```

Tool names are sanitized and joined into a comma-separated list through
`get_tool_names`. The prompt tells the model to output exactly one name from that
list.

Implication for this package: if keeping a text fallback, keep the tool list
small and exact. Include name, description, and input JSON schema. Do not include
Swift/Dart implementation details.

## ReAct Loop

The non-native loop is in
`lib/crewai/src/crewai/agents/crew_agent_executor.py`:

1. Send messages to the LLM.
2. Parse response into `AgentAction` or `AgentFinish`.
3. If action, execute one tool.
4. Append `Observation: <tool result>` to the assistant message.
5. Append that message to history.
6. Repeat until `Final Answer:` or max iterations.

The core observation append is in `handle_agent_action_core`:

```text
<model action text>
Observation: <tool result>
```

CrewAI uses the assistant message itself as the transcript of thought, action,
input, and observation. That is simple, but it means protocol text is part of the
conversation context.

## Parsing

The parser is in `lib/crewai/src/crewai/agents/parser.py`.

Accepted action shape:

```text
Thought: ...
Action: search
Action Input: {"query":"..."}
```

Accepted final shape:

```text
Thought: ...
Final Answer: ...
```

Important parser behavior:

- `Final Answer:` wins if present anywhere in the output.
- Action parsing uses a broad regex: `Action...: ... Action...Input...: ...`.
- Action input is stripped, then repaired with `json_repair`.
- Numbered labels like `Action 1:` and `Action Input 1:` are accepted.
- Missing `Action:` or `Action Input:` raises `OutputParserError`.

Tool input validation later accepts JSON, Python literal dictionaries, JSON5,
and repaired JSON. Non-dictionary inputs fail.

Implication for this package: if a fallback parser exists, keep it stricter than
CrewAI unless compatibility requires otherwise. Apple model output shown to users
must not accidentally parse prose as a tool call.

## Invalid Tool Calls

CrewAI handles invalid tool calls by feeding the error back into the same agent
loop.

Invalid format:

- `OutputParserError` is appended as a user message.
- A synthetic `AgentAction` is returned so the loop continues.
- After several errors, verbose logging prints parser failures.

Unknown tool:

- `_select_tool` does fuzzy matching with `SequenceMatcher` ratio `> 0.85`.
- If no match, it returns an error listing available actions.
- The error becomes the observation, so the model can retry.

Bad arguments:

- The tool input must parse to a dictionary.
- On repeated parse failure, CrewAI returns:

```text
I encountered an error: <error>
Moving on then. <format reminder>
```

Tool execution exceptions:

- Errors are converted into observations with the tool's accepted inputs.
- CrewAI may retry internally before returning the error to the loop.

Repeated tool use:

- Exact same tool name plus same arguments as the previous call is blocked by
  `ToolsHandler.last_used_tool`.

Implication for this package: avoid fuzzy tool-name matching. Genkit tool names
are stable identifiers; exact matching is safer. Return a structured tool error
to Genkit instead of teaching the model through assistant-visible protocol text.

## Max Iterations

Agents default to `max_iter = 25` in
`lib/crewai/src/crewai/agents/agent_builder/base_agent.py`.

Loop behavior:

- Each LLM/tool parsing cycle increments `iterations`.
- When `iterations >= max_iter`, CrewAI appends a force-final-answer message.
- It makes one more LLM call asking for the best final answer and stops.

Force-final-answer text from translations:

```text
Now it's time you MUST give your absolute best final answer. You'll ignore all
previous instructions, stop using any tools, and just return your absolute BEST
Final answer.
```

Implication for this package: keep Genkit as the iteration owner. If the provider
implements any local fallback loop, make it small and explicit. Do not hide a
25-step loop inside the model adapter.

## Native Tool Calling Split

CrewAI chooses native tools when:

```text
llm.supports_function_calling() && original_tools
```

Otherwise it falls back to text ReAct.

Native mode converts tools to OpenAI-style schemas and appends provider-native
tool call/result messages. Text-mode prompt instructions are skipped.

CrewAI also has a fallback message for providers that claim tool calling but then
reject tools: continue with text tool calling instead.

Implication for this package: match this hierarchy:

1. Prefer native FoundationModels tool capture.
2. Fall back to text tool-call markup only when native capture is unavailable.
3. Keep fallback isolated and documented as best-effort compatibility.

## Recommendations For `genkit_foundation_models`

Use CrewAI's text approach only as a fallback pattern.

Recommended fallback prompt:

```text
You may call one tool at a time.

Available tools:
{tool list with name, description, JSON input schema}

To call a tool, output exactly:
{"toolRequests":[{"name":"tool_name","arguments":{...}}]}

To answer, do not include tool-call JSON. Answer normally.
```

Keep these constraints:

- Exact tool-name matching only.
- JSON object arguments only.
- One tool call per model response unless Genkit request handling supports more.
- Strip protocol text from visible assistant text.
- Surface invalid tool calls as `ToolRequestPart` errors or model errors, not as
  user-visible prose.
- Let Genkit own max tool-loop iterations.
- Do not add role/goal/backstory as public API unless this package becomes an
  agent framework. It is currently a Genkit model provider.

Do not copy these CrewAI behaviors:

- Fuzzy matching unknown tool names.
- ReAct `Thought:` requirements.
- Assistant-visible `Observation:` transcript.
- Hidden high iteration count inside provider code.
- Prompt lines like "your job depends on it".

Best package direction remains the existing tooling-plan decision: native
FoundationModels tools capture tool calls; Genkit executes tools; this provider
maps structured transcript entries both directions. CrewAI confirms that prompt
parsing is a compatibility fallback, not the clean adapter boundary.
