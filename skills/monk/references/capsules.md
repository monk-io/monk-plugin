# Monk Capsules

A capsule is a production-like preview environment for one git branch. Every
branch gets its own copy of the app, deployed by Monk from the same MANIFEST,
with its own URL. The point is isolation: two branches (or two agents working
on two branches) must never read or write each other's data.

Isolation of compute is automatic. Isolation of anything the templates create
or name — databases, buckets, managed services behind entities, DNS names — is
only as good as the way the templates are parameterized. Most of the work of
preparing a project for capsules is that parameterization.

## How a Capsule Comes and Goes

`monk.capsule.setup` writes `.github/workflows/dynenv.yml`, mints a scoped API
key for the project, and stores the secrets the workflow needs in a GitHub
environment. From then on GitHub Actions drives everything:

1. **Push to a branch** (other than the excluded base branches). The workflow
   provisions the branch's target — in `cloud` mode a cluster of its own, named
   after the branch; in `cluster` mode a slot on one shared cluster — builds the
   MANIFEST's images, and deploys the MANIFEST's `ENTRY` workload. It also opens
   a `[capsule] <branch>` pull request that stands for the capsule's lifetime.
2. **Later pushes** rebuild and update the same capsule in place.
3. **Closing or merging that PR**, **deleting the branch**, or running the
   workflow with `action=destroy`, tears the capsule down. An hourly check also
   destroys the capsule of a branch that no longer exists, in case the delete
   was missed. Teardown nukes the capsule's
   cluster, which runs every entity's delete lifecycle, so managed resources the
   templates created are removed with it.
4. An optional up/down schedule (`monk.capsule.schedule.update`) stops and
   restarts capsules outside working hours.

`monk.capsule.list` shows each capsule's status and preview URL.

## What Each Capsule Receives

- **`environment`**: the deploy sets this variable on the `ENTRY` workload to
  the branch name, lowercased with anything outside `a-z0-9-` turned into `-`
  (`feat/Search` becomes `feat-search`). This is the value to build per-branch
  names from.
- **Its own cluster** (cloud mode), with its own node domain, container
  registry and ingress.
- **The MANIFEST's secrets**, copied from the GitHub environment into the
  capsule's cluster on every provision.
- **A preview URL**: the `entrypoint_url` of a `monkec/endpoints` entity in the
  entry workload's namespace when there is one, otherwise the cluster's node
  domain.

## Parameterize Per Branch

`environment` is set on the `ENTRY` workload, which is usually a group. Members
of a group inherit the group's variables, **unless a member declares a variable
of the same name — then its own declaration wins.** So:

- Declare `environment` once, on the entry group, with the value `main` (or
  whatever the default branch is) as the default for non-capsule deploys.
- Do **not** declare `environment` again on any member. A member that does
  keeps its default on every capsule, and every branch ends up sharing the
  resources named after it. `monk.capsule.setup` warns when it finds this.
- Build every name that must differ per branch from it: managed databases and
  clusters, database users, buckets, queues, DNS records, anything an entity
  creates outside the cluster.

```yaml
namespace: shop

stack:
  defines: group
  variables:
    environment:
      type: string
      value: main
  runnable-list:
    - shop/db
    - shop/api

db:
  defines: mongodb-atlas/cluster
  name: <- `shop-${environment}`
  # ... no `environment` declared here; it comes from shop/stack

api:
  defines: runnable
  # ... no `environment` declared here either
```

Things that are already per-capsule in cloud mode (the cluster, its volumes,
its node domain) need no parameterization. Things that live outside the
cluster always do: a fixed name there is shared by every branch, and the first
capsule to start will take ownership of what the others create.

Review these before running setup:

- Every entity whose name is a literal. If two branches would produce the same
  name, parameterize it.
- Connection strings and credentials the app builds itself. Escape user names
  and passwords, since generated credentials can contain URL-reserved
  characters.
- A health endpoint (`/health` or similar) that proves the app reached its own
  dependencies, so a preview can be checked rather than assumed.

## Cloud Mode or Cluster Mode

- **`cloud`** (default): one cluster per branch. Strong isolation, its own
  domain and ingress. Use this for anything with a web front end.
- **`cluster`**: every branch shares one cluster, namespaced by branch. Cheaper
  and faster to start, but branches share the node domain, so a web service
  needs its own host per branch. Have its route take the host from a stack
  variable: declare `ingress-host` (string, default `""`) on the stack and
  write `host: <- $ingress-host` next to `path-prefix: /` on the route. Deploy
  sets the variable to `<branch>.<node domain>` and reports that as the preview
  URL. Keep the `path-prefix`: an empty host leaves a plain `PathPrefix(/)`
  route, and a route with only an empty host has no rule and is dropped. The
  same variable can hold a real domain in production or dev. Without it only
  the first branch's web service is reachable: the others' runs succeed and
  report a preview URL that shows the first branch's app. Branches also push
  their images to the cluster's one registry, so an image tag that does not
  change between branches (`latest`) makes a node that already has it run the
  first branch's build for the others. Deploy does not tag per branch yet, so
  change the tag on the MANIFEST `IMAGE` line and the template's `image` in each
  branch (for example `app:<branch>`). Workers and APIs reached by internal
  address need no host, but the same image-tag rule applies.
  Setup warns when the cluster's node domain does not answer for subdomains (a
  node created before the platform did): the generated host will not resolve
  there, so use a new cluster for web previews.
  The cluster needs a worker node besides its system node (which runs the
  registry and ingress, never capsules). Setup tags the workers for capsules
  and refuses a cluster that has only the system node: add one with
  `monk.cluster.grow` first.

## Before Running Setup

1. The project deploys cleanly with `monk.project.deploy` to a normal cluster.
   Capsules run the same MANIFEST; a template that does not deploy will not
   deploy as a capsule either.
2. Per-branch names are parameterized as above.
3. The workspace is bound to a project (`monk.scope.bind`), in an org or in a
   personal account. Capsules need a paid plan: a personal account on the Free
   plan, or an organization without an active Team plan, can't run them,
   because every branch's capsule needs an environment of its own (and, in
   cloud mode, a cluster of its own). Setup refuses such an account and says
   so; tell the user to upgrade or start the Team plan rather than retry. When
   setup can't reach the platform to check, it goes on, and a later step that
   fails with a plan limit has the same cause.
4. In cloud mode the region and instance type are ones the provider offers:
   call `monk.cluster.catalog` for the provider and region and pick from it,
   rather than guessing a size. Setup checks them like cluster create does and
   refuses one that isn't offered, naming the valid ones. Providers retire
   sizes by region, so a size that worked last month may not work now.
5. GitHub credentials are stored (`monk.credentials.request`, provider
   `github`), and in cloud mode the cloud provider's too. The GitHub token
   needs Administration (write) on the repository in addition to the
   Actions, Secrets, Variables and Environments permissions the form lists.
6. Setup turns on "Allow GitHub Actions to create and approve pull requests"
   for the repository. If its result says it couldn't (the token lacks
   Administration, or an org policy forbids it), pass that step on to the
   user: without it the lifecycle PR cannot be opened, so closing it cannot
   tear the capsule down. Deleting the branch still does.

## When a Capsule Run Fails

The workflow and the monk-actions it calls are Monk's to fix. Do not edit
`dynenv.yml`, add steps that run Monk or call the actions' internal scripts,
or delete a capsule's cluster with `monk.cluster.delete` to get past a failure:
re-running `monk.capsule.setup` regenerates the file and drops the edits, and
a capsule torn down outside the workflow leaves its records and pull request
behind. Read the failing job's log, fix what is in the project (templates,
MANIFEST, secrets, app code), and report anything else with
`monk.feedback.submit`.
