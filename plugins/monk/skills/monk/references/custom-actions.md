# Custom Actions

A Monk package author can attach extra operations to a runnable or entity,
beyond the built-in lifecycle verbs — a database's `create-snapshot` and
`restore`, a cache's `flush`. These are **custom actions**, and they are code
the author wrote, executed against live infrastructure.

## Never Guess Whether One Is Safe

Monk cannot tell a read from a write. The daemon reports no such
classification, and the name is no guide: `list-snapshots` is usually harmless
and `restore` usually is not, but nothing stops an author from making the first
destructive. Treat an action's behavior as unknown until you have read what the
package says about it.

This is why every `monk.workload.do` call asks the user to approve the exact
action and argument values. The user may choose "always allow" for an action
they run often; that is their decision, recorded in the dashboard, and never
something to ask for or work around.

## Discover Before Invoking

Call `monk.workload.actions` first, always. It reports each action's name,
description, and arguments, and `monk.workload.do` refuses anything the target
does not declare. Passing an argument outside a declared schema is refused too,
rather than being silently dropped the way the daemon would drop it.

`monk.package.info` also summarizes a package's actions, which is useful when
comparing candidate packages before deploying one.

## The Two Flavors Differ, And One Of Them Is Undocumented

|                            | runnable action      | entity action            |
| -------------------------- | -------------------- | ------------------------ |
| listable before first run  | yes                  | no — needs runtime state |
| argument schema            | typed, with defaults | none at all              |
| missing required argument  | refused              | not checkable            |
| unrecognized argument name | refused              | accepted and ignored     |
| return value               | the action's result  | always `true`            |

Read `argsDeclared` on every action before passing arguments:

- **`argsDeclared: true`** — the schema is real. `args` lists each argument's
  type, whether it is required, and any default. Monk checks what you pass.
- **`argsDeclared: false`** — the package declares **no** argument schema, and
  this means _unknown_, not _none_. An empty `args` list here is not a claim
  that the action takes no arguments. Every entity action is in this state,
  because `monkec` compiles an `@action` method to a bare lifecycle entry and
  the argument contract does not survive compilation. Read the package's own
  documentation — `monk.package.dump`, or its README — before passing anything.
  An argument name the action does not recognize is accepted, ignored, and
  reported as success, so a typo produces a silent no-op rather than an error.

Every argument value crosses the wire as a **string**. Pass numbers and
booleans in string form (`retention_days: "14"`), which is also why entity code
coerces its own arguments.

## Reading The Result

`monk.workload.do` returns `output` (the lines the action printed) and `result`
(its return value).

For a **runnable** action the return value is the result — an action that
computes something answers there and often prints nothing at all. For an
**entity** action `result` is always literal `true`, so `output` is the only
real result; an entity action that reports nothing in its output has told you
nothing.

## An Entity Must Have Run Once

An entity's actions are resolved through runtime state, so they are only
listable after that entity has been deployed at least once. Being stopped
afterwards is fine — state survives a stop, and is gone only after a purge.
`monk.workload.actions` reports `reason: "needs_run"` for this case, which means
"deploy it first", not "something is broken".

## Trust Entries

`monk.workload.action.trust.list` shows the actions the user chose to always
allow, and `monk.workload.action.trust.revoke` withdraws one. Revoking is safe
at any time — it only ever narrows what runs unattended.

There is no tool that grants trust, by design. If a user wants an action
pre-approved, they tick the box on its approval in the dashboard. Do not ask
them to grant trust in order to unblock yourself; raise the approval and let
them decide.

A grant is confined to one action on one workload against one cluster. It does
not extend to a different action on the same workload, nor to the same action
after switching clusters.
