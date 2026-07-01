# LangChain Agent Tool Handling Notes

Research date: `2026-06-30T12:14:46Z`.

Sources checked:

- Context7 LangChain docs for agents, tools, and structured output.
- Web search excerpts for LangChain/LangGraph ReAct patterns current in 2026.
- Public LangChain docs examples showing structured `Tool Calls`, `Tool Message`,
  `return_direct`, and structured-output retry behavior.

## Summary

LangChain's current agent direction is structured tool calls through model/tool
interfaces and LangGraph nodes. Older ReAct-style prompt parsing remains useful
for models without native tool calls, but it is not the preferred reliability
path.

For this package, LangChain supports the same direction as the existing plan:
FoundationModels should use native structured tool capture, map calls into Genkit
`ToolRequestPart`s, inject results as structured tool history, and keep prompt
parsing as compatibility cleanup only.

## Prompt-Only ReAct Shape

Classic LangChain ReAct agents use this prompt grammar:

```text
Answer the following questions as best you can. You have access to the following tools:

{tools}

Use the following format:

Question: the input question you must answer
Thought: you should always think about what to do
Action: the action to take, should be one of [{tool_names}]
Action Input: the input to the action
Observation: the result of the action
... (this Thought/Action/Action Input/Observation can repeat)
Thought: I now know the final answer
Final Answer: the final answer to the original input question
```

This works only because the agent owns a parser and a loop:

1. Render tool names/descriptions in prompt text.
2. Ask model for `Thought` plus either `Action` or `Final Answer`.
3. Parse action text.
4. Execute tool.
5. Append `Observation` to scratchpad.
6. Repeat until final answer or max iterations.

The weakness is exactly what this package has been seeing: wrong tool selection,
format drift, repeated calls, and prompt-protocol text leaking into user-visible
output.

## Current Structured Tool Path

Modern LangChain examples show typed messages instead of prompt protocol text:

```text
Human Message
Ai Message
Tool Calls:
  tool_name (call_id)
  Args: ...
Tool Message
  {tool result}
Ai Message
  final answer
```

This is semantically the same loop as ReAct, but the model output is structured
as tool-call parts. The agent executes the tools and sends results back as tool
messages. Reasoning is usually hidden; the visible state is tool call, tool
result, final text.

Recommendation for this package:

- Keep Genkit as the loop owner.
- Keep FoundationModels as the structured provider adapter.
- Do not add an internal ReAct scratchpad loop inside the provider.

## Tool Definitions

LangChain tools include:

- `name`;
- natural-language `description`;
- argument schema, commonly Zod/Pydantic;
- optional direct-return behavior.

The model uses tool descriptions for selection. Bad descriptions lead to bad
tool selection; no agent framework can fully fix that at the adapter layer.

Recommendation:

- Preserve Genkit tool names and schemas exactly.
- Do exact tool-name matching only.
- Prefer concise, action-specific tool descriptions in examples/docs.

## Direct Tool Output

LangChain supports `return_direct=True` / `returnDirect: true` on tools. When a
tool output is already user-ready, the agent can return that output directly and
skip another model call.

This is relevant because FoundationModels can loop after a simple tool result.
For this package, direct return is not a provider concern unless Genkit exposes
that tool metadata. But the concept is useful:

- some tools should end the loop;
- final-answer reflection should run with tools disabled when needed;
- callers should control this policy, not hidden adapter prompts.

## Error And Retry Handling

LangChain structured-output docs show errors are fed back as tool messages when
the model emits invalid/multiple structured outputs. The model gets a retry with
clear feedback.

Useful rules:

- recoverable model mistakes become structured model feedback;
- retry messages should be concise and specific;
- exhausted retries should be visible as framework errors;
- tool execution errors are distinct from adapter/provider errors.

Recommendation:

- Keep native provider/generation failures as `FoundationModelsException`.
- Convert tool argument/schema problems into Genkit tool results only if Genkit
  exposes a safe path for that; do not execute side-effect tools with invalid
  args.
- Preserve debug transcript in the example app, because these loops are otherwise
  invisible.

## LangGraph Loop Shape

LangGraph's common ReAct graph is:

```text
agent node -> if tool calls, tools node -> agent node -> ... -> END
```

Termination is programmatic: no tool calls means end. ToolNode executes tool
calls, then returns results to the agent node. This is the clean shape Genkit
already approximates.

Recommendation:

- Do not move loop ownership into Swift.
- Provider returns either text or tool request parts.
- Genkit executes tools and re-enters provider with tool responses.
- Provider may offer a compatibility final-answer retry with tools omitted after
  provider failure, but not a hidden full agent loop.

## Fit For This Package

LangChain confirms this package should not grow a broad ReAct parser.

Keep:

- native FoundationModels capture tools;
- transcript/tool-output mapping;
- exact tool-name validation;
- exact completed-ref rejection;
- defensive parser only for fenced JSON tool-call output;
- debug UI showing each agent turn/tool request/tool result.

Consider adding:

- optional `returnDirect`-like behavior if Genkit/Dart tool metadata can expose it;
- explicit loop-policy docs: default Genkit loop, `foundationModelsToolLoopMode:
  singlePhase` for one final-answer pass after tool results;
- clearer retry/error taxonomy in docs.

Do not copy:

- broad `Thought/Action/Observation` parser;
- hidden scratchpad injected as assistant prose;
- fuzzy tool matching;
- adapter-owned multi-step loop.
