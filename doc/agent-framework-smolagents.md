# Agent Framework: smolagents CodeAgent

## Goal

Evaluate Hugging Face `smolagents` for agent tool use when native provider tool
calling is not required.

Research timestamp: `2026-06-30T07:16:03-0500`.

Source reviewed:

- `huggingface/smolagents`, cloned to
  `/var/folders/pt/yhlb769j4j1frcvj3mk_fy240000gp/T/opencode/agent-frameworks/smolagents`
- Context7 docs for `/huggingface/smolagents`
- `docs/source/en/guided_tour.md`
- `docs/source/en/tutorials/secure_code_execution.md`
- `src/smolagents/agents.py`
- `src/smolagents/prompts/code_agent.yaml`
- `src/smolagents/prompts/structured_code_agent.yaml`
- `src/smolagents/prompts/toolcalling_agent.yaml`
- `src/smolagents/local_python_executor.py`
- `src/smolagents/memory.py`
- `src/smolagents/utils.py`

## Short Answer

`CodeAgent` is useful as evidence that prompt-level code actions can work, but it
is the wrong adapter shape for this package when Apple Foundation Models exposes
native structured tool calls.

Use smolagents' ideas only for fallback or non-native providers:

- tool calls as explicit actions, not assistant prose;
- a single execution loop with observations fed back into memory;
- a reserved `final_answer` action;
- tight tool namespace and import allowlists when code execution exists.

Do not copy its Python execution model into this package unless this package
explicitly grows a code-execution agent. For Foundation Models, keep the native
tool-call boundary.

## Code Actions vs JSON Actions

Smolagents has two agent modes:

| Mode | Action format | Tool execution |
| --- | --- | --- |
| `CodeAgent` | Python code block | Executes generated Python in an executor |
| `ToolCallingAgent` | JSON-like tool call | Calls named tools with validated arguments |

`CodeAgent` prompt shape:

```text
Thought: explain next action
<code>
result = web_search(query="...")
print(result)
</code>
Observation: ...
```

Final answer shape:

```python
final_answer("answer")
```

`ToolCallingAgent` prompt shape:

```json
{
  "name": "web_search",
  "arguments": {"query": "..."}
}
```

Smolagents' docs argue code actions are more expressive because Python supports
composition, loops, state, and object manipulation. That is true for pure agentic
problem solving. It is not a reason to downgrade native structured tool calls to
text when the model/provider already exposes tool calls as typed events.

## Prompt Mechanics

`CodeAgent` uses `code_agent.yaml` by default.

Important prompt rules:

- always produce `Thought:` plus a code block;
- tools appear as Python function stubs from `tool.to_code_prompt()`;
- managed agents appear as callable Python functions too;
- use direct keyword arguments, not dict-wrapped arguments;
- use `print()` for intermediate values needed in the next step;
- call `final_answer(...)` to terminate;
- imports are limited to an authorized list;
- state persists between code executions.

`CodeAgent` can also use `structured_code_agent.yaml` when
`use_structured_outputs_internally=True`. That changes the model output to a JSON
object with `thought` and `code`, but the action is still Python code after
parsing.

Recommendation for this package:

- Native Foundation Models path should not use smolagents-style prompt tags.
- If a fallback text-only model is ever added, prefer the smallest protocol:
  `tool_name(args_json)` or fenced JSON, not full Python code execution.
- Only use code actions if the product goal is an agent that can compute and
  compose tools inside a sandbox.

## Tool Namespace

Smolagents exposes tools as names in the Python executor.

Mechanics:

- `MultiStepAgent._setup_tools()` builds `self.tools` as `{tool.name: tool}`.
- `final_answer` is always added if absent.
- managed agents share the same callable namespace.
- duplicate tool/agent names are rejected.
- `CodeAgent.run()` sends variables and tools to the executor before execution.
- `LocalPythonExecutor.send_tools()` makes tools callable from generated code.

Tool-call execution validates arguments before calling the tool:

- unknown tool becomes `AgentToolExecutionError`;
- invalid arguments become `AgentToolCallError`;
- tool exceptions become `AgentToolExecutionError` with retry guidance.

Recommendation for this package:

- Preserve Genkit tool names as the only callable namespace.
- Reject duplicate tool names before sending a request to Foundation Models.
- Keep a reserved final-answer concept separate from user tools if fallback loop
  needs it; do not let a user tool shadow it.
- Do not expose arbitrary Dart/Swift functions by name.

## Authorized Imports

`CodeAgent` has an import allowlist because generated Python can import modules.

Default authorized modules from `BASE_BUILTIN_MODULES`:

```text
collections, datetime, itertools, math, queue, random, re, stat, statistics,
time, unicodedata
```

`additional_authorized_imports` extends that list. Submodules are not implicitly
allowed: `numpy` does not allow `numpy.random` unless `numpy.random` or `numpy.*`
is authorized. `*` allows every package and logs a caution.

The local executor blocks obvious dangerous modules/functions and checks imports
through `check_import_authorized()`. Docs still warn that local execution is not a
complete sandbox; for untrusted code, use remote executors such as E2B, Docker,
Blaxel, or Modal.

Recommendation for this package:

- No import system is needed for native Foundation Models tools.
- If text/code fallback is added, default to no imports and no filesystem/network
  access.
- Do not offer `*`-style authorization in this package.
- Prefer host-defined tools over model-generated imports.

## Execution Loop

Smolagents agents inherit from `MultiStepAgent`.

Loop shape:

```text
TaskStep
while no final answer and step <= max_steps:
  optional PlanningStep
  ActionStep
    model.generate(...)
    parse action
    execute tool/code
    store observation/error
  append ActionStep to memory
if no final answer:
  ask model to provide final answer from memory
FinalAnswerStep
```

`CodeAgent._step_stream()` does this per action:

- writes memory to messages;
- calls `model.generate()` or `generate_stream()`;
- parses code from configured code-block tags;
- rewrites some accidental `final_answer = ...` assignments;
- yields a synthetic `ToolCall` named `python_interpreter`;
- executes code through `python_executor`;
- stores execution logs and last output as observation;
- yields `ActionOutput` with `is_final_answer` from executor result.

`ToolCallingAgent._step_stream()` does this per action:

- gets model output with `tools_to_call_from`;
- parses model-native or text-parsed tool calls;
- executes one or more tool calls;
- treats `final_answer` tool as terminal.

Recommendation for this package:

- Genkit already has the outer tool loop. Do not add a second hidden loop inside
  the provider adapter.
- Provider should map request -> Foundation Models transcript/tools -> structured
  response parts.
- Let Genkit execute tools and re-call the model with tool responses.
- If a fallback text loop is added, make `max_steps` explicit and return a clear
  max-step error, not partial assistant text that looks complete.

## Observations

Smolagents stores step data in `ActionStep`:

- model input messages;
- model output;
- code action;
- tool calls;
- observations;
- images;
- errors;
- action output;
- final-answer flag.

Memory replays observations as `TOOL_RESPONSE` messages with text:

```text
Observation:
...
```

For `CodeAgent`, observation text is:

```text
Execution logs:
...
Last output from code snippet:
...
```

Long content is truncated with a middle truncation marker.

Recommendation for this package:

- Preserve structured `ToolRequestPart` and `ToolResponsePart` data instead of
  serializing observations into text.
- Only stringify at the Foundation Models boundary if the native API requires
  text output.
- Preserve tool call id/ref, tool name, and structured JSON output.
- If truncation is necessary for logs, do not truncate structured tool results
  unless the caller opted into a size limit.

## Error Recovery

Smolagents distinguishes:

- `AgentGenerationError`: model call/generation failure, re-raised and stops run;
- `AgentParsingError`: action parse failure, stored as step error and retried;
- `AgentExecutionError`: code/tool execution failure, stored and retried;
- `AgentToolCallError`: invalid arguments;
- `AgentToolExecutionError`: tool failed;
- `AgentMaxStepsError`: no final answer before max steps.

On non-generation `AgentError`, the loop appends an error observation:

```text
Error:
...
Now let's retry: take care not to repeat previous errors! If you have retried
several times, try a completely different approach.
```

Unauthorized imports receive an extra warning suggesting
`additional_authorized_imports`.

Recommendation for this package:

- Native provider adapter should surface provider errors directly, not ask the
  model to recover from transport/runtime failures.
- Tool schema mismatch should fail before model call where possible.
- Model-issued invalid tool args should become a structured tool-call error only
  if Genkit supports retrying with that error as tool response.
- Do not hide repeated parse failures behind generic assistant text.

## Final Answer Detection

Smolagents final answer is an explicit reserved tool.

`CodeAgent` detection:

- `final_answer` is injected into static tools;
- executor wraps it to raise `FinalAnswerException`;
- `evaluate_python_code()` catches that exception and returns
  `CodeOutput(is_final_answer=True)`;
- outer loop stops when `ActionOutput.is_final_answer` is true.

`ToolCallingAgent` detection:

- a tool call named `final_answer` is terminal;
- multiple final answers or final answer plus other calls in one step is an
  execution error.

On max steps, `provide_final_answer()` asks the model for a final answer from the
current memory.

Recommendation for this package:

- Native Foundation Models final assistant text should be final text, not a fake
  `final_answer` tool call.
- In fallback text-loop mode, reserve `final_answer` and reject user tools with
  that name.
- Do not infer finality from plain prose when tool calls are still pending.

## Fit For Genkit Foundation Models

Smolagents solves a different problem: making generic LLMs act through code or
JSON when provider-native tool calling may not exist or may not be enough.

This package should optimize for a typed provider boundary:

```text
Genkit request
  -> Foundation Models transcript + native tools
  -> native model generation
  -> structured text/tool-call response
  -> Genkit ModelResponse
```

Borrow these smolagents ideas:

- explicit action/observation loop as fallback architecture;
- reserved terminal action if no provider-native final state exists;
- duplicate tool-name validation;
- step cap for any self-contained fallback loop;
- retry memory that includes parse/execution errors when text protocols are used.

Skip these smolagents ideas for the native path:

- Python code execution;
- imports and import allowlists;
- prompt-level `Thought/Code/Observation` protocol;
- parsing assistant text for native tool calls;
- injecting tool outputs as prose when structured transcript entries exist.

## Recommendation

For this package, keep the current design direction: use Apple Foundation Models
native tools/transcript concepts and map them to Genkit structured parts.

If native provider tool calling is not required for a future provider, add the
minimum fallback protocol:

1. JSON action only, not Python code.
2. One action per turn unless parallel calls are explicitly supported.
3. Reserved `final_answer` action.
4. Strict tool-name and argument validation.
5. Observations stored as structured tool responses where possible.
6. Explicit `max_steps` and parse-error retry messages.

Do not add a code executor unless there is a concrete user-facing need for model
generated computation beyond calling host tools. Code execution is high-agency,
hard to sandbox, and unnecessary for a Foundation Models provider adapter.
