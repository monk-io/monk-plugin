# Changelog

What's new in Monk. 59 releases between May 28 and October 2, 2026, newest first.

## Unreleased

## v0.1.68, 2026-10-02

- Shell commands that only mention `monk` inside a quoted search pattern, such as
  `grep -n "a\|monk" file`, are no longer blocked as if they ran the Monk CLI.
- In Google Antigravity on macOS and Linux, shell commands no longer fail with a hook error once the
  Monk plugin is installed, and Monk now starts by itself when a conversation begins there.
- Monk's command and template checks finish as soon as they have an answer, instead of keeping your
  coding agent waiting for up to their full time limit on macOS and Linux.
- Setup no longer reports Claude Code as failed in the default Windows console when the plugin
  installed fine, and a re-run no longer offers it again.
- Cursor and VS Code can now sign in to Monk. Monk refused their sign-in because they also offer a
  web address to return to, which it doesn't accept; it now keeps the addresses it does accept and
  goes ahead.
- When Google Antigravity is installed without its `agy` command, as on Windows, setup now adds Monk
  to Antigravity's MCP servers and tells you how to get the full plugin, instead of failing. A
  command that isn't installed is now named in plain words rather than "entity not found".
- Every item in Work now says which project it belongs to, in the list and under its title. A
  project your coding agent was asked to configure shows as handed off rather than queued forever,
  with what Monk asked the agent to do in a readable block instead of one line running off the
  screen. Skipped steps no longer show as finished, and runtime notices read as sentences rather
  than raw event data.
- A sign-in request from an app that didn't give its name now says so, instead of showing an
  internal id as if it were the app's name.
- An open dashboard tab reconnects by itself after Monk restarts, as soon as you have a dashboard
  session again (for example, once Monk opens a new tab), so pending approvals keep working without
  reloading the page. Until then it shows the reload banner and stops retrying every request.
- Monk now needs version 3.21.5 of the local Monk runtime. If yours is older, installing or updating
  Monk upgrades it for you, with your approval first.
- Work's filters take less room. Needs you, Active and All are tabs with a count on each, and the
  order, workspace and organization choices sit together in one Display menu. When the list shows a
  single workspace, its name sits beside the title and one click shows them all again.
- When the dashboard is open in a tab, it now plays a sound and shows a system notification when
  your coding agent needs an approval or a secret. Clicking the notification takes you straight to
  the request. Turn each one on or off under This machine, where you can also choose to bring the
  browser forward on every new request.
- The dashboard greets you properly when there's nothing to do. Work celebrates a clear inbox with
  what got finished today, and empty pages explain what will appear there, with a prompt to copy
  into your coding agent. Work also remembers your view and grouping across a refresh, and the
  delete confirmation no longer spills out of its box on narrow screens.
- The dashboard keeps its shape while it loads. Work shows its list and toolbar right away with
  placeholder rows, and moving between tasks no longer blanks their steps for a moment.
- Monk now checks that every download of Monk is signed by Monk before installing it. An update that
  fails the check is not installed, and the version you already have keeps working.
- When Monk can't check for an update, for example while you're offline, it now starts the version
  you already have instead of failing.
- When a deploy fails, its step log in the dashboard and in your coding agent now shows the error as
  readable text instead of an encoded string, and no longer says "Image ready" right after an image
  failed to download.
- A new `setup` command connects Monk to every coding agent it finds on your machine. You pick the
  agents from a checklist and review the plan before anything changes. It installs or updates the
  Monk plugin where the agent has plugins (Claude Code, Codex, Devin, Antigravity), and adds Monk's
  server and skill to the settings of the others, such as Zed, OpenCode, Cline, Goose, Warp and Amp,
  keeping your existing settings and a backup. Running it again brings an older Monk up to date. It
  ends with a summary of what worked and offers to sign you in, which you can skip.
- Install Monk and connect your coding agents in one line:
  `curl -fsSL https://get.monk.io/stable/plugin | sh`, with a matching PowerShell one-liner on
  Windows. Running it again updates Monk.
- Apps that can only run a local tool over standard input and output, such as Claude Desktop, can
  now use Monk through a new optional `mcp-stdio` command. It starts Monk if it isn't running, signs
  you in with the same browser approval as everywhere else, and connects. It is optional: the normal
  local connection keeps working and stays the default for Claude Code, Codex, Cursor and the rest.
- Opening Cursor on a machine where Claude Code also has the Monk plugin no longer restarts Monk
  each time and leaves your agents unable to reach it for about a minute.
- When your coding agent names a project folder on a call, Monk now uses that project's cluster,
  environment and secrets for it. After your coding agent reconnected, such a call could resolve the
  cluster of the folder the agent was started in, so a deploy or delete aimed at one project could
  have gone to another project's cluster while still naming the right folder.
- Selecting a cluster in the dashboard now applies to the workspace shown in the header, and
  credentials you enter for an organization, project or environment are saved for the project that
  asked for them, instead of for whichever coding agent connected to Monk last.
- When your coding agent names a folder outside the ones it shared with Monk, the call now fails and
  says so, instead of quietly running against the shared folder.
- Retrying a cluster grow after your coding agent reconnects now reports the grow already in
  progress instead of starting a second one.
- The dashboard no longer keeps listing coding agent connections that have ended.
- Hardening for how sessions are matched to the coding agent that opened them.
- Monk now works when your coding agent is installed as a strictly confined snap, such as Claude
  Code from the Snap Store. Installing tells you what's going on instead of failing on permissions:
  it writes the install steps to a script you run once in a normal terminal. After that Monk starts
  reliably inside the sandbox, and deploys work from it: loading your project, building images,
  reading cluster costs and enabling ingress on a new cluster no longer need the Monk command-line
  tool or podman, since Monk on the host does the work. The one exception is a cluster whose nodes
  span more than one architecture, whose images still have to be built outside the sandbox.
- Enabling ingress on a new cluster is retried when Monk declines it, instead of the step reporting
  ingress as enabled when it wasn't.
- Creating a cluster on a cloud whose new nodes take a minute or more to open the registry port,
  such as DigitalOcean, no longer fails at the registry step with a login timeout. Monk now waits
  for the registry to become reachable and retries the login, so the first create finishes without
  you having to run it again.
- On Windows, a deploy, grow or delete refused because another operation is already running on the
  cluster now names that operation, so your coding agent can follow its progress instead of only
  being told to try again later.
- Your coding agent can now list the blobs stored on a cluster and delete one it no longer needs,
  after you approve the deletion in the dashboard.
- Hardening for how project files are read during a deploy.
- Two workspaces using Monk on the same machine no longer silently get in each other's way. The
  machine has one Monk daemon, and a cluster create in one workspace used to pull it out from under
  a local deploy in another. A cluster create, a cluster exit and a provider setup now wait their
  turn: while a local deploy runs they are refused with a "busy" message naming the deploy, and a
  local deploy is refused the same way while one of them runs. A deploy that finds the daemon moved
  to another cluster anyway (for example by the Monk CLI) now fails and names both clusters instead
  of reporting success. Workload status, stop and delete now say which cluster they looked at, and
  "not found" explains when the workload is in a cluster the daemon has since left, and that nothing
  was deleted.
- When a cluster creation was cut off and its cloud nodes could not all be cleaned up, retrying it
  now names the leftover nodes and asks you to delete them in your cloud provider's console, instead
  of quietly starting over while they keep billing.

- Retrying a cluster creation right after a restart now finishes it, as promised in v0.1.67. If the
  cloud nodes were still being provisioned, the retry used to refuse and ask you to come back in up
  to about 20 minutes. It now checks whether provisioning is actually still running: it finishes the
  cluster as soon as the nodes are up, and starts over right away when nothing is left provisioning.
- After a cluster node gets a new domain, preparing or resetting the cluster registry now moves it
  to that domain and its certificate. Before, the registry kept the old domain, so image pulls
  failed certificate checks. Preparing the registry keeps its password; the login for the old
  address is removed and other registry logins are left alone.
- Security hardening to cluster registry credentials.
- Security hardening to cluster credentials.
- Approving a registry password reset now tells you what stops working until it is updated: the
  registry secrets your GitHub Actions use and any other logins to the registry. Re-run CI/CD setup
  afterwards to refresh them.
- A cluster left behind by an interrupted creation can now be deleted by the name the interruption
  message gives. Before, deleting it by name said the cluster was not found, and only a delete with
  no name worked. A name that doesn't match now also says which cluster the machine is connected to.
- Deleting a cluster no longer ends with a warning that the local runtime could not be disconnected
  when the delete had already disconnected it.
- After the local Monk service restarts, your coding agent reconnects instead of carrying on with a
  connection that can no longer remember its workspace. Before, a session set up after the restart
  was forgotten on the next call, and every call needed the session id passed by hand.
- In Codex, Monk now checks your MANIFEST and templates after Codex edits them through a shell
  command, not only through its file-editing tool, and tells Codex about any errors it finds. The
  command's own output is left as it was.
- Your coding agent can now renew an expired or expiring certificate on a cluster node, including
  the one the cluster registry uses. The node keeps its domain, so the registry address and your CI
  settings stay valid. The registry and ingress restart to serve the new certificate, and Monk
  checks that they do before reporting success. Before, the only way out was to give the node a new
  domain, which changed the registry address.
- On Windows, installing, upgrading or repairing Monk in your own Ubuntu WSL distro no longer
  replaces its `/etc/wsl.conf`. Monk only turns systemd on and keeps your other settings (network,
  mounts, default user), saving the original as `/etc/wsl.conf.monk-bak` first. The distro is
  restarted only when systemd isn't running yet, instead of on every install, upgrade and repair,
  which stopped whatever you had running in it. If your WSL is too old to run systemd, Monk now says
  so and asks you to run `wsl --update` instead of failing later.

## v0.1.67, 2026-09-29

- The dashboard's Work list shows the newest items first within each group.
- Credential requests in the dashboard's Work list show the provider logos they ask for next to the
  key icon.
- A credential request now reads "1 credential required" or "3 credentials required" instead of a
  count of sections. In the dashboard, choosing to enter OAuth credentials manually no longer traps
  you there: a link brings back the authorize button.
- Cloud and service credential requests in the dashboard show the provider's logo (AWS, Azure, GCP,
  MongoDB Atlas, Neon, GitHub and the rest), and the Vault's cloud accounts are picked from logo
  tiles instead of a dropdown. The light theme now uses the pastel Monk mark, like the dark one.
- The local dashboard is reorganized around what you look at. Clusters is now a table that opens
  onto one page per cluster, with its details, live map, the secrets that apply to it, and forget
  and delete. Credentials became Vault, split into cloud accounts, local secrets and cluster
  secrets. A new This machine page collects what used to sit behind the status bar's Details: Monk's
  health, where it keeps secrets, connected editors, and diagnostics. Old links to the cluster,
  cluster map and credentials pages still work. The status indicator and the Sign in button no
  longer spill out of the narrow, icon-only sidebar.
- Monk keeps working through long sessions. Commands it ran behind the scenes could leave files open
  when they timed out or left a helper process running, and after an hour or so of use every deploy
  and status check failed with "Too many open files". Those are now always closed, a timed-out
  command is stopped along with anything it started, and on macOS the background service is allowed
  far more open files. If it ever does run out, the error now says so and how to restart the
  service, instead of reading as a failed deploy.
- A dashboard tab left open while Monk restarts (after an update, for example) now says so: a banner
  asks you to reload the page, with a button to do it, and a click on an approval explains the same
  instead of showing "invalid csrf token" while the request still looked like it was waiting on you.
  Approving a workspace's organization or project is no longer labeled a destructive action that
  can't be undone, since you can always bind it again; it still needs your approval.
- Retrying a cluster creation that was cut off by a restart now picks up the interrupted attempt and
  finishes it. It used to start over, find the nodes the first attempt had made, and tell you to run
  the creation again, which then refused because the cluster already existed. When a creation does
  find a same-named cluster with nodes, it now points you to checking, growing or deleting that
  cluster, the same advice the next attempt gives.
- A cluster creation, grow or deletion cut off by a restart now warns that cloud nodes may already
  be running and billing, and names the steps to check the cluster's machines and to finish or
  remove it. A request made after a restart without a workspace now says to start the session again.
- Installing Monk on Windows now finishes starting the local runtime where your coding agent can
  reach it. It used to leave the runtime running but unreachable, so every deploy failed until it
  was restarted by hand. Install status now also reports that situation instead of calling the
  runtime ready, and an install step that fails inside WSL is now reported as failed rather than as
  done.
- The dashboard has a new Environments page: a live map of your app as it runs in each of its
  environments, drawn from the environment's own cluster. It shows each workload's health, your
  clouds and machines, and where ingress is served. It stays current by itself, and keeps its layout
  as things change.
- Each cluster on the dashboard's Clusters page now has a map of everything it runs: every
  environment's apps side by side, or one environment at a time, with the environments hosted on the
  cluster listed below and linked to their Environments page.
- A deploy review's Tree tab now matches the rest of the review: every workload and field in one
  indented list, with an entity's data and schema changes shown key by key and hidden values marked.
- Adding nodes to a cluster now opens the same editable review as creating one, instead of a yes/no
  approval: change the machine type, count, region or disk before approving, see the estimated cost,
  and see a diagram of the cluster's machines now next to the new ones. Cluster creation's review
  draws the machines it provisions too, and shows its steps once approved.
- Deploy reviews have a new What it builds tab: a diagram of the app the deploy creates, with what
  changes marked (new, updated, recreated, scaled, removed), your cloud and cluster as zones,
  managed databases and buckets beside the cluster, and a note on anything the diagram can't know
  yet. Ingress on a host that isn't publicly reachable is flagged. For an app that is already
  running, the diagram comes from what your cluster actually runs: every connection's target, which
  container serves each service, and which volumes are mounted where.
- Deploy approval previews now render an entity's data and schema as an expandable tree — nested
  objects and array fields each get their own row, with a collapse toggle — instead of one long line
  of text.
- Approving a cluster creation at the moment it times out, or approving and cancelling it from two
  tabs, now settles on one outcome and reports it once, instead of reporting both. Two identical
  cluster creations started at the same time now start one cluster, not two.
- A finished task no longer changes status afterwards: a late failure or an interrupted run
  finishing after a restart can no longer rewrite how it ended. Clearing task history while a task
  is logging no longer brings cleared tasks back.
- Installing Monk no longer reports the runtime as already ready when everything it needs is in
  place but the runtime itself isn't responding; it now says what's wrong instead.
- Cluster changes (create, grow, delete) started from two sessions at the same time now always run
  one after the other; before, both could occasionally run at once. If Monk quits or crashes in the
  middle of one, the next no longer waits several minutes before it can start.
- Checking Monk's status, or starting it a second time, while it's already running no longer cancels
  approvals you haven't answered yet or marks operations in progress as interrupted.
- Installing Monk no longer hangs when a step stops responding, never starts a second copy of an
  install that is still running, and stops everything it started when it gives up on a step.
- If starting Monk shows that it also needs an upgrade, the install now asks you to approve the
  upgrade too, instead of stopping halfway.
- Install errors now say which step failed and why, including when a step ran out of time.
- Installing Monk on Linux no longer reports that apt or dnf is missing when checking for them
  fails.
- Submitting a secret, certificate or credential form from two dashboard tabs at once now keeps
  exactly one submission, instead of losing the value or applying a different certificate than the
  one recorded. A submission that fails to save can now be retried.
- Two cluster operations running at once no longer overwrite each other's progress, which could make
  a failed cluster creation start over instead of resuming.
- Cluster creation no longer deletes a cluster whose nodes are still coming up after a slow or
  interrupted provisioning. The nodes are kept, and running the same create again finishes the
  cluster, or removes the empty cluster if no nodes were made.
- A cluster creation interrupted by a restart no longer blocks creating that cluster again: running
  the same create resumes it or starts over, and a resume that fails can itself be resumed.
- Cluster creation now stops if it can't tell which cluster the local daemon is in, instead of
  provisioning nodes into a different cluster and reporting success.
- Creating a cluster with the name of an existing one is now refused, instead of provisioning a
  second cluster under the same name. A cluster kept after a partly failed creation is recorded, so
  you can grow or delete it.
- A cluster renamed while reviewing its plan is now the one resumed or cleaned up after a failure.
- Growing a cluster no longer holds up other cluster operations while it waits for your approval to
  register that cluster.
- Deploying no longer logs in to the cluster registry before you approve the plan. A denied or
  timed-out plan now says that nothing running changed.
- Two deploys to the same cluster no longer run at once, and a deploy no longer runs while that
  cluster is being grown or deleted. The second one is refused and points you at the one already
  running.
- Switching clusters while a deploy runs no longer sends part of it to the other cluster.
- A failed deploy now says which step it stopped at and what it had already changed, and a deploy
  interrupted by a restart says the workload may be partly updated.
- Deleting or forgetting a cluster from the dashboard now only ever acts on the cluster you
  approved. Before, if selecting that cluster failed, the one already selected could be deleted
  instead.
- If Monk's local secret storage can't be opened, Monk now reports that when a secret is next used
  instead of shutting down.
- Security hardening.

## v0.1.66, 2026-09-21

- Updating capsule secrets that fail to write now records that failure in the operation's history,
  instead of reporting it as succeeded.
- Checking cluster registry status now distinguishes a transient failure to read the registry
  credentials from the registry genuinely not being configured, instead of reporting both the same
  way.
- Looking up available GPU accelerator types now explains why none were found, instead of returning
  an unexplained empty list.
- Listing ingress certificates when the ingress plugin isn't enabled no longer errors out — it now
  reports the same disabled status ingress status already does.
- Reading recent agent activity no longer includes activity from other workspaces bound in the same
  agent process — it now scopes to the current workspace, matching the feed and deploy history.
- Unloading a workload template that's currently running now warns you it's live before you approve,
  instead of silently leaving it running and no longer manageable by name.
- Configuring a project no longer claims no deployment configuration exists when one already does —
  it now checks first, instead of always deferring to author new files from scratch over a working
  deploy.
- Checking infrastructure usage for a personal account for the current month now works when the
  month is passed explicitly, not just when it's omitted.
- Checking cluster pricing when the daemon reports a well-formed result alongside a failure exit
  code now surfaces that result cleanly, instead of showing the raw response as an error.
- Reading the account-wide scope catalog now actually reports account-wide owner/project data,
  instead of duplicating the current workspace's own scope.
- Watching a deploy now reports what Monk is actually doing at each step — image pull progress,
  script output, and errors — instead of repeating one generic progress line for every event.
- Setting up CI/CD now checks that the connected GitHub token can actually push to the repository
  before asking you to approve the plan, instead of after — a token that could only read a public
  repository no longer sails through approval and only then fails on the write it required.
- Initializing a session for a workspace whose path can't be resolved now fails with a clear error,
  instead of silently binding to a different, phantom identity and stranding any secrets stored
  under it where they can never be found again.
- Cluster names are now checked against the strictest real cloud-provider naming rules up front,
  instead of accepting a name a later step could still reject — or silently mismatch — once a
  provider was chosen.
- Creating a cluster with an empty or invalid name is now rejected up front instead of silently
  falling back to a generic default name.
- Your coding agent can now discover the custom actions a package attaches to a workload — a
  database's snapshot and restore operations, for example — instead of only the built-in lifecycle
  verbs. It also reports when a package declares no argument schema for an action, so it points you
  at that package's own docs rather than guessing at argument names that would be silently ignored.
- Your coding agent can now run a package's custom actions — taking a database snapshot, restoring
  one — instead of only reporting that they exist. You approve the exact action and every argument
  value in the dashboard first, and can tick "always allow" on an action you run often. Monk can't
  tell whether an action only reads or also changes things, so nothing runs unattended unless you
  said it could, and you can withdraw that at any time.
- Running a custom action that returns a value instead of printing output now reports that value,
  instead of saying it produced no output.
- Security hardening to resetting Monk's local state.

## v0.1.65, 2026-09-17

- Real, running clusters no longer disappear from your local list minutes after being created. A
  cluster whose registration with the platform never succeeded was indistinguishable from one that
  had been deleted on the platform, so the background sync removed the only local record of live,
  billing infrastructure. Clusters the platform does know about are now also recorded as registered,
  so they can't be mistaken for unregistered ones later.
- Binding a cluster to an organization or project that the platform rejects now reports the failure
  instead of returning success with the error buried in a message, and the cluster's registration
  state now records what actually happened.
- Deleting or forgetting a cluster that was never successfully registered with the platform no
  longer fails permanently on the platform deregistration step — which left real infrastructure with
  no way to remove it through Monk at all.
- Creating a cluster against a project that doesn't exist now fails before any nodes are
  provisioned, instead of after roughly nine minutes of real cloud spend. A confirmed missing
  project blocks; billing, permission, or network problems reading it do not.
- Creating a cluster from a workspace that isn't bound to an account or organization now refuses up
  front, rather than provisioning infrastructure that could never be registered afterwards.
- Listing secrets across all scopes, or viewing them in the dashboard, after switching clusters no
  longer shows another cluster's organization, project, or environment secrets — entries are now
  matched against the selected cluster's own organization/project/environment.

## v0.1.64, 2026-09-16

- Checking cluster provider availability, estimating cluster costs, checking cluster pricing,
  browsing/searching/inspecting packages, or reading workload logs, when the local runtime isn't
  installed or running, no longer tells you to create a cluster or leaks a raw connection error —
  each now correctly points you at installing or starting the runtime first.
- Installing or updating the plugin no longer waits forever when another install is stuck holding
  the shared installation lock — it now gives up after a bounded wait and reports a clear error
  instead of hanging your coding agent's session indefinitely.
- Starting the plugin with automatic updates skipped no longer restarts an already-running, healthy
  companion on every session on macOS/Linux — it now reuses it, matching the existing Windows
  behavior.
- Uninstalling on Windows now waits for the companion process to fully exit before removing its
  files, instead of proceeding immediately after asking it to stop.
- Uninstalling the plugin on Windows now removes Monk's registration from Antigravity's global MCP
  configuration, instead of leaving a dead server entry behind.
- Uninstalling on macOS now actually stops the running companion process, instead of only removing
  its tracking file and leaving it running.
- Deleting a workspace or project registration, an organization role, or a saved cluster record that
  was never registered now reports that there's nothing to delete, instead of a false success.
- Removing a cluster peer, or resetting one's certificate, now checks the peer actually exists in
  the cluster instead of sending the request regardless.
- Listing organization-scoped secrets on a personal account no longer relabels your personal secrets
  as organization secrets — it now reports them the same way adding or removing an organization
  secret already correctly refused to.
- Checking ingress status right after re-enabling it no longer reports an error for a recovery that
  actually succeeded — the health result is now reported alongside the certificate domains instead
  of being replaced by a transient failure reading them.
- Checking ingress status now distinguishes a transient failure to read Traefik's state from ingress
  genuinely being disabled, instead of reporting both the same way.
- Installing or updating the plugin no longer hangs indefinitely if the download starts but then
  stalls partway through — it now gives up and reports a failure instead of leaving your coding
  agent stuck waiting.
- Binding a cluster to an environment name that doesn't exist yet used to silently create it and tag
  every peer with it — Monk now asks before creating a new environment this way. Clearing a
  cluster's environment link now actually unlinks it on the platform and removes the peer tag,
  instead of reporting success while the old link stayed in place.
- Deploying with a cluster target and a conflicting local-only override (or the reverse) is now
  rejected instead of silently deploying locally and reporting success.
- Deploying to an environment name that isn't declared anywhere in your project now fails clearly
  instead of silently deploying the default entry.
- Re-binding an already-bound workspace without repeating its project now keeps that project,
  instead of silently treating the omission as "move to no project" and asking you to confirm a move
  that was never intended. Confirming a genuine move now also names the actual destination,
  including when it's clearing the project entirely, instead of a vague "the new owner/project".
- Binding a workspace to an organization no longer registers unrelated clusters from your other
  workspaces under that organization's project — only clusters belonging to the workspace you just
  bound.
- When binding a workspace also requires picking between multiple accounts or confirming a move, the
  approval now says so upfront if it will also register any of your existing local clusters with
  that organization, instead of only doing it silently afterward.
- Binding a cluster you've already bound to the same organization/project no longer re-asks to copy
  existing secrets into it every time — only a genuinely new organization/project association does.
- Binding a cluster no longer asks to copy existing secrets when there's nothing anywhere to copy —
  such as an organization's very first cluster.
- Unbinding a cluster from an organization now correctly updates the platform, instead of silently
  failing to reflect the change there.
- Binding a cluster no longer asks to remove now-out-of-scope secrets when its KV never had anything
  at the scope it's leaving.
- Additional hardening to how a cluster's secrets are kept in sync with its current organization,
  project, and environment.
- Creating a cluster while an unrelated environment was still selected no longer tries to link the
  new cluster to that environment — only an environment you explicitly ask for gets linked.
- Reading logs for a workload whose container has already stopped now says so, instead of returning
  logs that look like a healthy, running service.
- Deploying no longer reports success when the deployed workload isn't actually running afterward —
  it now fails so you know to look.
- Listing a cluster's peers or providers for a cluster your workspace hasn't adopted yet now says
  so, instead of looking identical to an adopted cluster.
- Growing or creating a cluster no longer reports success before its new node has actually joined —
  it now confirms the join and, if a node never appears, fails clearly naming how many actually did.
- Growing a cluster now refuses to add cloud nodes to the local, credentials-only cluster shell, and
  points you at creating a real cluster instead. Dashboard error messages now show the actual reason
  for a failure instead of a generic status code.
- Reading logs for a workload identified by an ambiguous short name now fails clearly instead of
  silently guessing — which could otherwise show a different workload's logs.
- Setting a preference with an empty key is now rejected, instead of being stored and read back to
  you as a blank key.
- Storing a very large secret in the fallback encrypted vault, used only when your OS keychain isn't
  available, no longer crashes — large values now encode correctly.
- Removing or re-adding an account-wide secret from a workspace other than the one that created it
  now works correctly, instead of silently failing or creating a duplicate entry.
- Adding or requesting a secret with an empty or invalid name is now rejected outright, instead of
  being stored as a malformed entry. Secret tool descriptions now also explain that your local vault
  and a cluster's own secret store are separate, synced only when you deploy — so the two not
  matching isn't a bug.
- A cluster whose creation failed partway through, after its nodes were already provisioned, now
  keeps its organization and project association when it's preserved for a retry — instead of
  becoming invisible to every organization-scoped tool until you re-bind it by hand.
- Setting an ingress certificate now records the request before contacting the cluster, so a slow or
  failed connection leaves a visible, cleanly-cancelled request instead of vanishing with no trace.
- Resetting a cluster peer's certificate now checks the peer actually exists before opening the
  approval, matching the other peer operations.
- Upgrading a cluster to a version that doesn't actually exist is now caught before the upgrade
  approval opens, instead of failing partway through the upgrade itself.
- Updating a capsule's schedule now validates the times, weekdays, and timezone before opening the
  approval, so what you approve is what actually gets saved. It also refuses to schedule a capsule
  that was never set up, explaining why instead of silently accepting it.
- Removing a watcher that was never deployed now says so, instead of reporting it as removed — and
  no longer opens an approval before checking whether it's deployed at all.
- Watcher operations now recognize a cluster peer as local or remote the same way status checks do,
  instead of using a narrower check that could misclassify one.
- Stopping, deleting, or unloading a workload that doesn't exist now fails immediately, instead of
  opening an approval for an operation that could never succeed.
- Additional hardening to cross-cluster secret resolution during deploy, and to how role changes are
  validated and reported.

## v0.1.63, 2026-09-08

- Security hardening.

## v0.1.62, 2026-09-07

- Reconnecting a MongoDB Atlas connection now offers to reuse your existing service account instead
  of always creating a new one, so projects and clusters it already manages stay reachable.

## v0.1.61, 2026-09-04

- Listing workspace registrations, deleting a workspace/project/environment registration, and
  re-binding an already-bound workspace now default to the workspace's own owner scope when none is
  given, instead of an error that misleadingly claimed an organization was requested.
- Deploying now explains when a required secret couldn't be filled in because its connected service
  (MongoDB Atlas, Netlify, etc.) isn't set up yet, instead of a generic "secret not found" error.
- Additional hardening to how deploy resolves secrets from connected service credentials.
- Listing stored credentials now flags a connected service's own internal entry as internal, with a
  note on how to actually use that connection in a template, instead of leaving your coding agent to
  guess from a bare name.
- A slow deploy, cluster, or workload operation that outlasts your coding agent's own wait no longer
  tells it to open a dashboard approval link that was already approved (or denied) in the meantime.

## v0.1.60, 2026-09-03

- Hardening and reliability fixes to the safety checks Monk runs inside your coding agent.
- The check that reviews a file no longer silently produces nothing — it could previously hang on
  Windows, or come up empty on Linux.
- Infrastructure usage now explains that a cluster's "stopped"/"running" status there tracks cost
  reporting, not whether the cluster is connected — a cluster can show "stopped" while genuinely
  live and healthy.

## v0.1.59, 2026-09-02

- **New** Preview what deploying a project would change without deploying, building, or running
  anything.
- **New** Deploying now asks for approval in the dashboard with the full plan in front of you: a
  tree of what gets created, updated, or removed, field-level differences, cost impact, and
  warnings. It appears whenever the plan finds real changes.
- **New** A cluster your machine is already connected to but that Monk never registered — one
  created outside the plugin, or before you installed it — can now be selected and bound to a
  workspace. It used to be invisible to every cluster command even while status reported it fine.
  Monk asks before registering it.
- **New** A central audit trail. Dashboard approvals record who approved or denied each request, and
  cluster plan approvals, secret, credential, and certificate prompts, and tool actions all reach an
  organization-wide audit log.
- Signing in with MongoDB Atlas (or entering Netlify, Vercel, Neon, Stripe, Cloudflare, Redis Cloud,
  or DigitalOcean Spaces credentials) now also fills any MANIFEST secret your templates bind to that
  provider, whatever it is named. Previously only the default secret names were recognised, so a
  project whose Atlas entity read its token from a custom-named secret asked you to paste the same
  service-account key into a second form right after signing in, and the deploy failed until you
  did.
- Installing Monk on macOS now actually starts the local runtime. It used to watch for the runtime
  to come up without ever starting it, then give up after ninety seconds having changed nothing —
  and do the same on every retry. Creating the virtual machine on a Mac that never had one now works
  from the same install run.
- The safety checks Monk runs inside your coding agent now give up after a few seconds when the
  local runtime stops responding, and fall back to their safe default. A stuck runtime used to hold
  each check open for your agent's entire timeout, freezing the session.
- Pushing secrets to a cluster now needs an explicit list of names. The mode that pushed every
  locally stored secret when you omitted the list is gone.
- Deleting a cluster now checks that the name you gave matches the cluster you have selected. It
  used to ignore a mismatched name and destroy whichever cluster was selected.
- When cluster deletion fails partway, Monk tries to restore the platform record and tells you
  whether that restore worked, was queued for retry, or failed. It used to report a single generic
  "unlinked".
- Removing or pushing secrets across several clusters reports which clusters failed, which
  succeeded, and which never had the secret, instead of blanket success or failure when only some
  clusters were reachable.
- Stopping, deleting, or unloading a workload checks the target exists first and reports how many
  were affected. A typo in a name or tag used to report success having matched nothing.
- Built-in system workloads such as the ingress controller are recognised anywhere in their path, so
  they can no longer be caught by a stop or delete aimed at something else.
- Cluster and ingress status report ingress as enabled and healthy for a standalone local runtime
  serving TLS traffic. It used to report disabled purely because the runtime was not part of a
  multi-node cluster.
- Removing a secret or credential no longer raises a destructive "cannot be undone" prompt for a
  name that does not exist, and an unrecognised name is rejected upfront rather than skipped
  silently.
- Submitting feedback works when you are signed out of the dashboard, which is the situation the
  fallback exists for.
- Commands that reach the platform, such as feedback, pricing, and cost estimates, time out and
  report the problem instead of hanging when a token refresh stalls.
- An abandoned sign-in request expires after ten minutes rather than staying pending forever.
- Switching to a different custom executable path now stops the previous process. It used to keep
  running in the background while the switch reported success.
- Deleting a secret in the dashboard shows progress while it runs, and a failed row stays visible
  with an explanation instead of disappearing.
- Local deploys that ask for a specific tag warn you when that tag is ignored, rather than dropping
  it silently.
- Security hardening.

## v0.1.58, 2026-08-18

- Forgetting a cluster now looks up its real owner before deregistering it, so the request can no
  longer go to the wrong organization based on stale local data.
- Deleting a cluster now says plainly when its platform record could not be removed, instead of
  reporting the record as gone either way.
- A connection error from the workspace analysis service no longer takes Monk down with it.
- Searching packages by prefix now matches only packages that start with it.
- Setting up a cloud provider no longer fails on a fresh cluster with no credentials stored yet.
- On macOS, the automatic runtime upgrade now updates the runtime inside the Monk VM. It used to
  report the runtime as permanently out of date instead.

## v0.1.57, 2026-08-14

- **New** Attach GPU accelerators when creating or growing a cluster. Monk checks the type and count
  before provisioning anything, so an invalid combination is rejected before you are billed for a
  node. The approval prompt now shows the accelerator, which is usually the largest line in the
  bill.
- **New** One-click sign-in for MongoDB Atlas credentials. It previously fell back to filling in a
  form by hand.
- The cluster catalog and creation form now show real GPU specifications: model, count, and memory,
  rather than a yes/no flag.
- Fixed being locked out of the dashboard for the rest of a session whenever Monk could not open a
  browser for you. This hit anyone working over SSH, in WSL, in containers, or on a headless
  machine, and it broke sign-in, secret and credential requests, cluster approvals, certificate
  requests, and workload approvals. There is now always a working link, and the locked page offers a
  real way back in.
- Sign-in shows which account you are about to use, so picking the wrong one is visible beforehand.
- Switching to a cluster outside your current scope now gives a clear error. It used to clear your
  selection silently, and the next command failed with "no active cluster connected".
- Fixed many cases where a real connection failure looked like an empty or disconnected state rather
  than an error. This affected cluster status, watcher status and setup, provider attachment, deploy
  targets, certificate status, and cluster growth.
- Workload removal and watcher checks no longer report success when they failed or only partly
  finished, and a partly-failed push of continuous-delivery secrets no longer goes unnoticed.
- Project diagnostics can now tell a clean project from one missing its manifest. Both used to
  report "no issues found".
- Cost estimates, instance catalogs, and GPU lookups no longer come back empty on the first call
  after you add new provider credentials.
- Several Windows fixes for the Antigravity launcher, including a stale registration after a port
  change and a malformed configuration file that could stop startup.
- The dashboard's plain pages now follow your light or dark preference, and have a favicon.
- Security hardening.

## v0.1.56, 2026-08-10

- Fixed the Windows installer failing outright on headless hosts and Windows Server Core.
- A brief network problem during the update check no longer stops startup when a verified
  installation is already on the machine.
- "Forget cluster" now detects that you are still joined to the cluster you are forgetting. It could
  previously discard the only information needed to leave cleanly.

## v0.1.55, 2026-08-07

- Deploys that failed their final health check were reported as "successfully deployed". They now
  report as failures.
- Container registry setup no longer reports the registry as ready when the login to it failed.
- Listing secrets across scopes no longer drops one when the same name exists in two scopes, and
  organization secrets are no longer mislabelled as account secrets.
- Package and operator search now handles multi-word queries where the match is in tags or a
  description, or the words are out of order.
- A role's permissions can no longer change while its assignment is awaiting approval, so what you
  approve is what gets granted.
- Deleting a cluster that then fails to disconnect cleanly now warns you instead of hiding it.
- Fixed a restart race that could leave Monk reporting itself healthy while it was down.
- Dashboard accessibility fixes. Screen readers now announce the active navigation link, the
  collapsed sidebar's status button is clickable, and filter buttons show their pressed state.
- Security hardening.

## v0.1.54, 2026-08-05

- Tool calls awaiting your approval now return a clickable link and a way to check status. They
  sometimes timed out with nothing you could act on.
- An approval link now always matches the operation it was issued for. Two similar requests arriving
  at once could previously be shown against each other.
- Sign-in failures show the real reason, such as "please verify your email before logging in",
  rather than a generic error.
- Fixed several Windows launcher races. The single-instance lock could be bypassed, concurrent
  installs on different ports could corrupt each other, and the launcher could start an unrelated
  program from your PATH instead of the managed installation.
- The launcher can no longer stop an unrelated process whose id happened to be reused.
- The Windows launcher now registers the Antigravity integration, matching macOS and Linux.
- Updating the plugin on Windows restarts Monk, so it stops reporting a stale version.
- Security hardening across several areas.

## v0.1.53, 2026-08-04

- **New** Sign out and switch to a different Monk account. Signing in again used to reuse whichever
  account was already connected. The consent screen now names the account in use.
- Switching accounts requires fresh consent for connected tools. Approvals no longer carry over from
  the previous account.
- The Windows installer download is about eight times faster, six seconds rather than forty-six,
  which fixes startup timeouts in editors that wait for it.
- Fixed several Windows and WSL installation problems: incorrect "ready" reports, administrator
  prompts hanging with no terminal to answer them, proxy settings not reaching the installer, and
  older distributions going undetected.
- Re-running the installer over an existing installation skips the redundant download. It used to
  download everything again and then fail to update.
- The uninstaller no longer reports success when removal failed, and can no longer delete a Linux
  distribution it did not create.
- Fixed startup crashing for Antigravity users whose home directory contains an apostrophe.
- Security hardening across several areas.

## v0.1.52, 2026-07-29

- Destructive local actions now require your approval in the dashboard: clearing Monk's local state,
  deleting stored credentials, removing local secrets, and choosing which organization a cluster
  belongs to. They used to trust a flag your coding agent could set on its own, so instructions
  hidden in a file or a web page could reach them.
- Deploys that fail partway now show as failed instead of staying "running" forever.
- Installation waits until a service is reachable before continuing. It used to report "already
  ready" while the service was still starting.
- Long installations are tracked as an action you can check on, rather than blocking the request
  until they finish or time out.
- Cluster ingress setup no longer reports success after exhausting its retries.
- Submitting credentials through the dashboard no longer reports success when the save failed, and
  concurrent submissions no longer cause one to vanish.
- Fixed the Windows version appearing to go down and restarting every session. This also broke
  startup in editors such as VS Code and suppressed the Windows sign-in prompt.
- Security hardening.

## v0.1.51, 2026-07-27

- Sensitive cluster and workspace operations now go through the right approval and permission
  checks: sending a stored cloud credential to a cluster, binding a cluster to an organization,
  switching or forgetting a cluster, deleting a workspace, project, or environment, and updating a
  scheduled environment.

## v0.1.50, 2026-07-27

- Dashboard status polling no longer creates hundreds of redundant audit entries every hour.
- Uninstalling Monk stops an Antigravity-launched companion on every platform and removes its
  registration. It used to leave an orphaned process behind.
- Fixed a spurious hook error appearing on every command, edit, and session start in Claude Code and
  Cursor on macOS and Linux.
- Installers detect a corrupted zero-byte download instead of trusting it indefinitely, and
  concurrent installations no longer corrupt each other.
- Local health checks bypass a configured proxy, handle IPv6 loopback addresses, and confirm they
  are talking to Monk rather than another service on the same port.
- Fixed the launcher restarting every session when using a custom binary path, and not picking up
  changed configuration without a manual restart.

## v0.1.49, 2026-07-24

- Codex now runs the command-safety and diagnostics hooks properly. They failed to start from a real
  project, and diagnostic output was dropped before the model saw it.
- Security hardening.

## v0.1.48, 2026-07-23

- **New** Upgrade the cluster runtime on a single machine, across a whole cluster one machine at a
  time, or locally.
- The cluster list sorts your selected cluster first, then reachable ones, then most recently
  updated. Cluster detail shows each machine's status, name, and version.
- Joining the same cluster from more than one workspace no longer creates duplicate entries.
- The displayed version now matches what shipped.
- Events reaching your coding agent through the workspace feed are stripped of personal details,
  such as email addresses, before they leave Monk.

## v0.1.47, 2026-07-22

- **New** Set custom certificates for cluster machines and the shared ingress, from the dashboard or
  through Monk's tools.
- The Antigravity startup notice confirms the companion is reachable before saying it started, and
  no longer misreports a running companion as stopped on minimal systems.
- Fixed garbled text in installation status and diagnostics on non-English Windows systems, and
  improved right-to-left display.
- Monk's local status check reports only whether you are signed in, with no account details
  attached.

## v0.1.46, 2026-07-21

- Clusters whose registry hostname stops resolving now fall back to a known address, which fixes
  deploys to self-hosted clusters with broken name resolution.
- Fixed a first-launch crash on machines that can reach Monk but not GitHub. It stopped the
  companion from starting at all.
- Launcher and uninstall scripts recognise a crashed background process instead of waiting out the
  full timeout, tolerate stale state files, and confirm a process's identity before stopping it.
- Security hardening.

## v0.1.45, 2026-07-18

- Configuration guidance warns that leaving persistent storage off a stateful service loses its data
  on the next deploy.

## v0.1.43, 2026-07-17

- Monk no longer restarts forever when its port is in use. It defers to a healthy instance already
  running, or exits with a clear explanation.
- Growing a cluster without naming the new machines numbers them after the cluster itself, so
  "acme-prod" grows by adding "acme-prod-1".
- Ingress health no longer reports "unhealthy" while it is serving traffic with a ready replica.
- The dashboard refreshes cluster and credential information as you move between pages, instead of
  showing minutes-old data.
- On Linux, a transient credential-store error no longer reports you as signed out.

## v0.1.42, 2026-07-13

- **New** Sync team members, and share secrets across organization, project, and environment scopes
  with role-based access control.

## v0.1.41, 2026-07-13

- Deleting or forgetting a cluster can unlink any environments still pointing at it first, and skips
  a redundant confirmation.

## v0.1.40, 2026-07-10

- Removing a cluster's last machine, or the machine running its system services, is now blocked so
  you cannot destroy a cluster by accident.
- Cost estimation during cluster planning works reliably. It used to fail on missing provider
  credentials.
- On macOS, starting a machine that was never initialised now initialises it and retries instead of
  failing permanently.

## v0.1.39, 2026-07-07

- **New** Secrets, preferences, and role management, with a dashboard for credentials and roles.
  Secrets work across organization, project, environment, and account scopes.

## v0.1.38, 2026-07-07

- Fixed spurious "please sign in" prompts shown to users who were already signed in. Unnecessary
  restarts and transient credential-store errors were read as signed-out.
- Status checks are briefly cached and de-duplicated, so concurrent checks no longer pile up and
  time out under load.

## v0.1.37, 2026-07-05

- **New** Look up a provider's valid regions and instance types before creating a cluster. Monk
  validates your choices upfront rather than failing mid-provisioning.
- Long operations report that they are still running rather than appearing to fail while quietly
  continuing. This covers creating, growing, and deleting clusters, deploying, and configuring.
  Retrying such an operation was tempting and could provision duplicate infrastructure.
- Those operations stream live progress in agents that support it, including through multi-minute
  quiet phases and across network reconnects.
- Fixed a hang when creating a second cluster while the first was awaiting approval, and a cancelled
  creation leaving behind cloud resources that needed manual cleanup.
- Cluster errors come with a next step rather than a raw message.

## v0.1.35, 2026-07-01

- Automatic diagnostics reach Cursor as well as Claude Code.
- Monk's tool names are prefixed so they do not collide with other connected tools.

## v0.1.34, 2026-06-26

- Registry readiness checks no longer hang indefinitely.
- The command-safety and diagnostics hooks run on Windows through PowerShell, not only on macOS and
  Linux, and the diagnostics hook returns its findings.
- Security hardening.

## v0.1.33, 2026-06-25

- **New** Ingress and registry status. Cluster status reports both.
- Monk no longer exits when an internal operation fails unexpectedly. It stays running.
- On Windows, the connection to the local runtime no longer drops after a period of inactivity.
- Cursor and Codex detect that you are signed out and prompt you, instead of assuming you are
  already signed in.
- Installing on Linux without an interactive terminal now succeeds.
- Security hardening.

## v0.1.32, 2026-06-23

- **New** Cluster monitoring. Set up automated health and threshold watching with Slack alerts,
  check its status, or remove it.

## v0.1.31, 2026-06-23

- **New** Submit bug reports directly over HTTP, without going through Monk at all.

## v0.1.30, 2026-06-23

- **New** Submit bug reports through Monk without signing in first.

## v0.1.29, 2026-06-21

- **New** A "clear history" action removes finished tasks and approvals from the dashboard without
  touching your sign-in, secrets, or sessions.
- Secret names are now kebab-case: lowercase letters, numbers, and hyphens.
- Fixed Monk not starting automatically in Codex, and dashboard filter menus being cut off when the
  feed was empty.

## v0.1.28, 2026-06-17

- **New** Support for Antigravity, alongside Claude Code, Codex, and Cursor.
- **New** Deploy published packages without having the source code locally.
- **New** Credential setup handles providers that combine one-click sign-in with a form, such as
  Netlify.
- Approvals left pending by a crashed process are cleaned up on restart instead of sticking around
  forever.
- Fixed generated deploy configuration producing invalid routing rules, and the dashboard showing
  duplicate "needs input" entries for one operation.

## v0.1.27, 2026-06-12

- Deploy no longer breaks working ingress routing by falling back to plain ports and firewall
  changes when a temporary error occurs.
- Fixed cluster creation failing when enabling ingress immediately after growing a cluster.
- After a plugin update, Monk tells you to reconnect immediately. It used to spend minutes
  investigating a dead connection.
- Fixed installation and upgrade failing on newer Homebrew versions.

## v0.1.26, 2026-06-11

- **New** Deploy using cloud provider credentials directly, without provisioning a cluster first.
- **New** Continuous-delivery setup generates a GitHub Actions workflow that deploys on every push.
- Cluster deletion shows which cluster is about to be removed, with name, provider, and region.
  Deleted clusters disappear from the list instead of leaving a dead entry.
- Fixed a failed cluster creation leaving behind an undeletable cluster with no way to resume or
  clean it up.
- Installation detects an outdated runtime and offers to upgrade it.
- The dashboard reuses an open tab for approvals rather than opening a new one each time.

## v0.1.25, 2026-06-10

- **New** Scheduled-environment setup automates deploying to GitHub Actions, including pushing
  secrets and configuring schedules.
- Fixed clusters becoming slow and unreliable shortly after creation, and creation hanging while
  system services were still starting.
- Security hardening.

## v0.1.24, 2026-06-10

- **New** Cluster approvals show estimated hourly and monthly cost, with new tools to check
  organization usage and set billing alerts.
- **New** Creating a cluster enables ingress routing automatically.
- Binding an account that belongs to several organizations asks which one to use instead of choosing
  silently.
- Cluster creation cannot proceed without its approval actually being granted.
- Deleting an unresponsive cluster no longer hangs for up to twenty minutes.
- Workload logs return real output. They always came back empty.
- Security hardening across several areas.

## v0.1.23, 2026-06-08

- Fixed accounts incorrectly showing as not set up, which affected nearly every account.

## v0.1.22, 2026-06-05

- Deleted clusters no longer linger in the cluster list.

## v0.1.21, 2026-06-05

- **New** Monk keeps a rotating local log with sensitive values removed, useful for diagnosis.
- Fixed switching the active cluster in one session silently causing other sessions in the same
  workspace to act on the wrong cluster.
- New or drifted accounts are no longer stuck being told they are not set up. Setup completes
  automatically.
- Cluster operations on personal or unassigned accounts are no longer incorrectly blocked.
- Fixed deploys failing on macOS setups that reach Monk over an SSH tunnel.

## v0.1.20, 2026-06-04

- Cluster and deploy operations degrade gracefully during brief platform outages instead of failing
  outright.
- Setting up a cluster registry no longer needs an extra approval.
- Fixed audit entries being lost when a write was interrupted, and a crash during audit checks on
  Linux.
- Security hardening.

## v0.1.19, 2026-06-03

- The dashboard uses the Monk design system for a cleaner, more consistent look.

## v0.1.18, 2026-06-03

- Workload actions such as stop and delete no longer target a cluster other than the one you
  selected.
- Cluster creation interrupted partway retries and finishes registering and selecting the cluster,
  instead of leaving it half set up.

## v0.1.17, 2026-06-03

- Fixed the generated Codex marketplace listing.

## v0.1.16, 2026-06-03

- **New** Workload lifecycle controls, stop, delete, and unload, plus bounded log reading.
- Fixed the Windows automatic updater.

## v0.1.15, 2026-06-02

- **New** Send bug reports, integration requests, and feature requests to the Monk team from inside
  Monk.
- **New** Secret and credential fields have a generator for a secure random value, and a show/hide
  toggle.
- **New** Credential forms for Azure and Google Cloud accept the provider's credentials file
  directly, rather than copying each field by hand, and link to the provider's instructions.
- The cluster creation form offers real regions, zones, and instance types from your chosen provider
  instead of free-text fields, so invalid input is impossible.
- Already-resolved requests no longer accept resubmission from a stale browser tab, which could
  overwrite the recorded outcome.
- Prompts reopen an existing browser tab instead of spawning a new one each time.

## v0.1.14, 2026-06-01

- Fixed installation on Windows through WSL, which broke silently on path separators and line
  endings.
- Fixed local and cluster deploys on Windows failing with file-not-found and authentication errors.
- Fixed cluster deploys failing with a gateway error during registry sign-in, pull, and push, on
  every platform.

## v0.1.13, 2026-05-31

- **New** The dashboard lists connected clients and lets you revoke any one of them. Signing out
  revokes them all.
- Security hardening.

## v0.1.12, 2026-05-30

- **New** Windows support. Monk runs its commands through WSL.
- Installation is more reliable. It no longer fails when a service is slow to start, and it resumes
  where it left off after a reboot or crash rather than starting over.
- Fixed Cursor sign-in redirects, which failed for both native and loopback addresses.
- Security hardening.

## v0.1.10, 2026-05-28

The first public release of the Monk plugin, connecting Claude Code, Codex, Cursor, and GitHub
Copilot to Monk, so you can create clusters and deploy applications in plain language.

- **Approvals you control.** Creating clusters and deploying workloads go through explicit approval
  gates, with live progress. Approvals, secrets, credential requests, and cluster forms appear
  together in one feed.
- **Cluster and project tools.** Status, machines, providers, and project configuration, plus
  browsing Monk's package and operator catalogs from your coding agent.
- **One command to reset.** Clear all local state, credentials, secrets, and approvals at once. It
  leaves your Monk sign-in token alone.
- **Available as a plugin.** Install from the Claude Code, Codex, Cursor, and GitHub Copilot
  marketplaces.
- **Sign-in that stays signed in.** Tokens refresh before they expire, and sign-in works from
  editors that redirect to a native application.
- **Install diagnostics.** Detailed probe results, how components relate, troubleshooting hints, and
  a recommended next step.
- **Cross-platform storage.** Secrets use the system credential vault, falling back to encrypted
  local files on Windows when it is unavailable. Linux installs set the runtime up through systemd.
- **A dashboard worth looking at.** Light and dark themes, icon-based navigation, a live status
  indicator, and faster loading.
- Your workspace is detected automatically from Claude Code and other editors.
- Cluster creation and deployment get up to twenty and thirty minutes, so long operations can finish
  rather than time out.
