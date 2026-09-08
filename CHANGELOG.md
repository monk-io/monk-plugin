# Changelog

What's new in Monk. 53 releases between May 28 and September 7, 2026, newest first.

## Unreleased

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
