# Agent Framework Synthesis

Research date: `2026-06-30T12:14:46Z`.

Inputs:

- `doc/agent-framework-langchain.md`
- `doc/agent-framework-llamaindex.md`
- `doc/agent-framework-autogen.md`
- `doc/agent-framework-semantic-kernel.md`
- `doc/agent-framework-crewai.md`
- `doc/agent-framework-smolagents.md`
- `doc/agent-framework-haystack.md`
- `doc/agent-framework-pydantic-ai.md`
- `doc/genkit-foundation-models-tooling-plan.md`

## Decision

Keep the package as a structured FoundationModels provider adapter. Do not turn it
into a ReAct agent framework.

The best shape remains:

```text
Genkit ModelRequest
  -> FoundationModels Transcript + native Tool wrappers
  -> captured native tool calls
  -> Genkit ToolRequestPart
  -> Genkit executes tools
  -> Genkit ToolResponsePart
  -> FoundationModels Transcript.ToolOutput
  -> final text or another structured tool call
```

Prompt-parsed tool calls should remain compatibility cleanup, not the primary
tool path.

## Cross-Framework Pattern

Every reviewed framework separates two modes:

| Mode | Used when | Reliability |
| --- | --- | --- |
| Structured/native tool calls | Provider supports tool/function calls | Preferred |
| Prompt protocol parsing | Provider lacks structured tools | Fallback |

Prompt protocol examples use `Thought`, `Action`, `Action Input`, `Observation`,
and `Final Answer`, or a narrow JSON/code block. They work only because the
framework owns a parser, retry prompts, observations, and a max-step loop.

This package should not copy that loop because Genkit already owns model/tool
orchestration.

## What Is Better Than Our Old Prompt

The old package prompt asked Apple to print a custom protocol payload in
assistant text. That is weaker than what frameworks do because it mixes assistant
text and tool protocol in the same channel.

Better patterns from frameworks:

- Tool calls are separate typed events or strict parsed actions.
- Tool results are separate typed observations/messages.
- Final text is final text only.
- Tool errors are fed back as structured observations, not generic prose.
- Iteration stops on structured conditions: no tool call, final answer, max steps,
  direct-return tool, or caller policy.

Our native capture implementation matches the better structured path. The prompt
fallback should stay small and defensive.

## Keep

- Native FoundationModels `Tool` wrappers.
- Capturing native tool calls in Swift and returning `NativePart.toolRequestJson`.
- Genkit as the tool executor.
- Mapping Genkit tool responses to FoundationModels `Transcript.ToolOutput`.
- Exact tool-name matching.
- Exact completed-ref rejection.
- Cumulative snapshot-to-delta streaming handling.
- Retry without tools after FoundationModels fails on a tool-response turn.
- Example app debug transcript showing hidden model/tool turns.
- `foundationModelsToolLoopMode: singlePhase` as caller-controlled policy.

## Change

### 1. Document Tool-Loop Policy

Current behavior should be explicit in README/API docs:

- Default: tools remain available while Genkit loops.
- `foundationModelsToolLoopMode: singlePhase`: after tool results, run one
  final-answer pass without tools.
- Provider may retry without tools on `generationFailed` after tool output.

This mirrors AutoGen/LangChain reflection while keeping the user-requested default
where the final user/caller decides whether tools keep looping.

### 2. Treat Prompt Parsing As Fallback Cleanup

Current parser accepts fenced/bare JSON array payloads only as fallback cleanup.
Docs should say:

- native tool capture is primary;
- text parsing is leak prevention and compatibility;
- text parsing is not guaranteed agent semantics;
- malformed fallback JSON remains text or errors predictably.

Do not add full `Thought/Action/Observation` parsing.

### 3. Improve Tool Description Guidance

Agent frameworks cannot fix bad tool choice at adapter level. Tool selection
quality depends heavily on tool names/descriptions/schemas.

Add README guidance:

- use narrow tool names;
- descriptions must include when to use and when not to use;
- prefer required schema fields for tools that need input;
- avoid huge all-purpose tools;
- expose fewer tools when tasks are narrow if caller wants deterministic behavior.

### 4. Consider Direct-Return Metadata Later

LangChain has `return_direct`. AutoGen has tool summaries/reflection. PydanticAI
has output tools that terminate runs.

If Genkit exposes equivalent tool metadata later, the provider/example can honor
it by ending after a tool result or by forcing a final no-tools pass. Do not invent
package-specific direct-return API yet.

### 5. Keep Recoverable Errors Structured

Consensus:

- unknown tool, malformed args, validation failure, and tool exception should be
  model-readable tool results when the agent loop can recover;
- provider transport/runtime failures should throw typed exceptions;
- exhausted retries should expose transcript/debug info.

Genkit owns most tool execution, so this package should only handle provider-side
errors and invalid native tool requests. The example app should keep logging full
turns.

## Do Not Add

- Provider-owned hidden ReAct loop.
- Broad regex parser for `Thought/Action/Observation`.
- Fuzzy tool-name matching.
- Assistant-visible `Observation:` scratchpad.
- Code execution (`smolagents` style).
- Hidden prompt-based tool scoping.
- High default loop cap inside the provider.

## Recommended Package Tests

Keep existing tests and add/ensure these cases:

- Native capture call maps to `ToolRequestPart` without prompt tags.
- Multiple native calls preserve order and refs.
- Tool response history maps to native `toolOutput`, not prose.
- Same tool name can be called again with a new ref.
- Exact completed ref is rejected.
- Fenced JSON fallback parser does not expose raw tool JSON.
- Malformed fallback tool JSON does not execute a tool.
- `singlePhase` omits tools on the turn immediately after tool responses.
- Default mode keeps tools available.
- Generation failure after tool response retries once without tools.

## Recommended Example Behavior

The example should stay honest and debuggable:

- pass all tools by default;
- offer manual tool selection for experiments;
- show exposed tools per turn;
- show all model turns, tool requests, tool results, errors, and final text;
- offer `singlePhase` toggle;
- do not secretly block model-chosen tools;
- use local deterministic tools instead of network/search tools for debugging.

## Priority

1. Update public docs for native structured tool path and loop policy.
2. Keep parser fallback defensive only; do not expand it.
3. Keep/example improve debug transcript and copy-log UX.
4. Revisit direct-return only if Genkit exposes equivalent metadata.

## Final Recommendation

Do less in this provider, but make the boundaries sharper.

The package should be a reliable translation layer between Genkit and Apple
FoundationModels. Agent planning, dynamic tool scoping, retry budgets, and complex
multi-step policies belong in Genkit or the caller. The provider should preserve
structured messages, avoid visible protocol leaks, and expose clear configuration
for the one behavior it must affect: whether tools stay available after a tool
response.
