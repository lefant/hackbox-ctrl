# Control Host And Target Agent Readiness

## Purpose

Define the required behavior for two machine roles:
- general machines, meaning provisioned VMs that host a project workspace
- the active control host, which adds control-plane and fleet-management responsibilities on top of the general-machine baseline

This spec is the high-level source of truth for readiness expectations, but it does not require every expectation to be covered by the same validation mechanism.

The current validation tooling and procedure split is documented in:

- `docs/reference/readiness-validation.md`

The intended validation split is:

- **Smoke tests** cover fast, deterministic checks that are suitable for repeated automated execution during provisioning and regression checks.
- **Interactive acceptance tests** cover session-shaped behavior that is better validated by a coding agent or operator over SSH, shell, tmux, and live agent interaction.

Unless otherwise specified, readiness requirements may be satisfied by either:

- automated smoke-test evidence, or
- interactive acceptance-test evidence

depending on which mechanism is more reliable for the behavior being validated.

## Requirements

The readiness requirements are grouped by the shared bucket model documented in:

- `docs/decisions/2026-03-26_adopt-shared-nix-bucket-layering.md`

## Deployment Applicability

Readiness expectations apply according to the enabled bucket set for the deployment type.

| Deployment type | Expected buckets | Notes |
| --- | --- | --- |
| Host-only toolnix bootstrap | `R + O + A` by default | Home Manager-managed host state without requiring a project checkout |
| General machine minimal | `R + A` | Neutral project-capable VM/runtime baseline |
| General machine with opinionated shell | `R + O + A` | Default host-style ergonomics added on top of baseline |
| Control host | `R + O + A + H` | Full control-plane workstation |
| Opted-in admin target | `R + A + H` or `R + O + A + H` | Target VM explicitly granted management behavior |

### Host-only Toolnix Bootstrap Readiness

The system SHALL support a host-only bootstrap path that produces the expected managed host state without requiring a checked out project repository on the target machine.

**Validation preference:** primarily deterministic smoke checks, with optional interactive acceptance afterward.

**Scenarios:**
- GIVEN a fresh exe.dev VM is provisioned through the host-only toolnix bootstrap path WHEN readiness is checked THEN `claude` and `pi` are on `PATH`.
- GIVEN that same host-only bootstrap path WHEN readiness is checked THEN managed files such as `~/.claude/settings.json`, `~/.claude/skills`, and `~/.pi/agent/settings.json` exist.
- GIVEN the host-only bootstrap path is used from a control host WHEN target state is inspected THEN the target does not require a target-side clone of `toolnix` for the bootstrap to succeed.

### Delegated Project-Target Bootstrap Readiness

The system SHALL support a delegated project-target bootstrap path that provisions a fresh exe.dev VM, consumes `toolnix` through a remote flake bootstrap, installs the declared project checkout, and reaches a working `devenv`-capable state without requiring target-side clones of shared bootstrap repos.

**Validation preference:** deterministic fresh-VM proof plus smoke tests, followed by optional interactive acceptance.

**Scenarios:**
- GIVEN a fresh exe.dev VM is provisioned through `scripts/provision-exe-dev-nix.sh` WHEN the delegated remote bootstrap runs THEN the target reaches Home Manager-managed host state through the tracked `toolnix` remote bootstrap script rather than an inline ad hoc bootstrap implementation.
- GIVEN the delegated project-target bootstrap path is used on a fresh VM WHEN cache configuration is applied THEN the path fails early unless `cache.numtide.com` is actually active in `nix config show` for the target runtime.
- GIVEN the delegated project-target bootstrap path has activated the cache-backed host baseline WHEN `devenv` is installed and initialized THEN `devenv shell -- printenv DEVENV_ROOT` succeeds for the declared project checkout without the earlier large local build failure mode.
- GIVEN the delegated project-target bootstrap path is reproved on a fresh VM WHEN smoke tests run THEN deterministic checks for shell baseline, agent baseline, zsh completion, and `devenv` environment entry succeed.
- GIVEN the delegated project-target bootstrap path uploads machine-local auth artifacts from control-host inventory WHEN a target agent uses Codex, Claude, or Pi THEN success depends on the freshness of the uploaded machine-local auth state rather than on target-side repo clones.

### R: Required Shell/System Baseline Readiness

The system SHALL provide the required shell/system baseline on general machines, control hosts, and normal project-capable guest runtimes.

**Validation preference:** mixed. Provisioning-preflight and smoke tests should cover deterministic access/tooling checks; interactive acceptance should cover session-shaped proof.

**Scenarios:**
- GIVEN provisioning is about to configure a target VM WHEN the provisioner reads the target and shared credentials THEN it verifies that `GH_TOKEN` is available for that target.
- GIVEN a target VM is being provisioned for a project repository WHEN the provisioner validates GitHub access THEN it confirms the configured `GH_TOKEN` is sufficient for both pull and push operations against that repository's remote.
- GIVEN the configured `GH_TOKEN` is missing or lacks sufficient repository permissions WHEN provisioning runs THEN provisioning fails explicitly before claiming the target is ready.
- GIVEN a user SSHs into a general machine WHEN they open a shell in the checked out project repository THEN the shell has the expected baseline commands including `bat`, `git`, `gh`, `tmux`, and a valid UTF-8 `LANG` locale.
- GIVEN a user is on a general machine WHEN they check for editor support THEN `mg` is installed on the machine as part of the required baseline package set.
- GIVEN a user is in the checked out project repository on a general machine WHEN they run `gh auth status`, `git pull`, and `git push` THEN the configured GitHub credentials support the repository's normal remote workflow.
- GIVEN a validation session is active on the active control host WHEN `gh auth status`, `git pull`, and `git push` are run in `~/git/lefant/hackbox-ctrl-inventory` THEN GitHub CLI access and normal git remote operations succeed there as well.

### O: Opinionated Shell Baseline Readiness

The system SHALL make the shared opinionated shell baseline available on inventory-managed hosts by default. Stockholm `TZ` is expected in both Home Manager-managed host shells and `devenv`.

**Validation preference:** primarily interactive acceptance coverage.

**Scenarios:**
- GIVEN a user SSHs into a general machine WHEN they open a shell in the checked out project repository THEN the shell has the expected opinionated commands and ergonomics including `e`, Stockholm time, and the tmux helper entrypoints when that baseline is enabled.
- GIVEN a user SSHs into an inventory-managed host WHEN they inspect `TZ` and `date` in the managed shell THEN `TZ=Europe/Stockholm` is present and the reported time is not UTC.
- GIVEN a user is on a general machine WHEN they use the `e` alias THEN it resolves to an editor command that is at least equivalent to `mg -n`.
- GIVEN a user is in the project repository on a general machine WHEN they run `tmux-here` or the machine's default tmux entrypoint THEN a usable project tmux session starts with the expected tmux configuration.
- GIVEN a user is in the project repository on a general machine WHEN they run `tmux-here` or the machine's default tmux entrypoint THEN tmux starts without config warnings such as invalid shell paths or invalid color settings.
- GIVEN a user is inside tmux on a general machine WHEN they inspect the tmux status bar THEN the displayed clock reflects Stockholm time.
- GIVEN a user is inside a `tmux-here` session on a general machine WHEN they inspect the session environment and status bar THEN `TMUX_COLOUR` is set and the status bar color is derived from the project repo, branch, and VM hostname rather than using the default tmux green.
- GIVEN the validation tmux session is active on a general machine WHEN `which e`, `type e`, and `echo $TMUX_COLOUR` are run and the tmux status bar is inspected THEN the opinionated shell baseline is visibly active and coherent.

### A: Agent Baseline Readiness

The system SHALL make the default agent baseline available on general machines, control hosts, and normal agent-capable guest runtimes.

**Validation preference:** mixed. Basic binary/auth/ping coverage is suitable for smoke tests; prompt usability, wrapper behavior, and skill ergonomics are better handled by interactive acceptance.

**Scenarios:**
- GIVEN the user is inside a project tmux session on a general machine WHEN they run `pi` THEN Pi starts without first-run setup blockers, renders a readable UTF-8-capable prompt, and is usable interactively.
- GIVEN the user is inside a project tmux session on a general machine WHEN they run `pi` THEN Pi does not emit missing-auth or missing-credential warnings before ordinary use.
- GIVEN the user is inside a project tmux session on a general machine WHEN they use Pi input keybindings THEN Pi supports:
  - newline via `ctrl-j`, `ctrl-m`, `shift-enter`, `alt-enter`, and `enter`
  - submit via `alt-j` and `alt-m`
  - queue-follow-up via `alt-q`
  - restore queued messages via `alt-up` and `alt-p`
- GIVEN the user is inside a project tmux session on a general machine WHEN they run `claude` THEN the shell alias expands to `claude --dangerously-skip-permissions --model opus` and Claude starts without first-run setup blockers, renders a readable UTF-8-capable prompt, and can complete at least a simple ping-to-pong style prompt-response check.
- GIVEN the user is inside a project tmux session on a general machine WHEN they run `codex` THEN the shell alias expands to `codex --yolo` and Codex starts without first-run setup blockers, renders a readable UTF-8-capable prompt, and can complete at least a simple ping-to-pong style prompt-response check.
- GIVEN the user is inside a project tmux session on a general machine WHEN they run `codex` in the checked out project repository THEN Codex does not stop on a workspace-trust confirmation prompt for that repository.
- GIVEN the user is inside a project tmux session on a general machine WHEN they test multiline entry behavior in Codex and Claude THEN `ctrl-j`, `ctrl-m`, and `shift-enter` produce newline behavior to the degree those agents support it in their current CLI builds.
- GIVEN an agent is running on a general machine WHEN it enumerates installed skills THEN custom skills from `lefant/agent-skills` are present.
- GIVEN an agent is running on a general machine WHEN it performs ordinary project-local work THEN it can use the configured GitHub credentials and local project environment without requiring general control-plane administration capabilities.
- GIVEN the validation tmux session is active on a general machine WHEN `claude`, `codex`, and `pi` are launched in turn THEN each agent demonstrates authenticated prompt execution.
- GIVEN the validation tmux session is active in the checked out project repository WHEN `codex` is launched normally THEN no directory-trust confirmation prompt appears before the ordinary Codex prompt.
- GIVEN custom skills are installed on the general machine WHEN one of the agents is asked to use a custom skill THEN the skill is discoverable and usable during the session.

#### Optional A Extensions

The base `A` readiness requirements above apply to ordinary agent-capable hosts. Additional opt-in agent capabilities may define extra readiness checks without becoming part of the mandatory baseline for all machines.

##### Agent-Browser Opt-In Readiness

When `agent-browser` is explicitly enabled for a host or project consumer, the system SHALL provide a usable host-native browser automation path without requiring Docker by default.

**Validation preference:** mixed. Presence of the wrapper and first-run install flow are suitable for smoke checks; real browser interaction is best handled by interactive acceptance.

**Scenarios:**
- GIVEN a project or host has explicitly enabled `toolnix.agentBrowser.enable` WHEN the user enters the corresponding shell THEN `agent-browser` is present on `PATH`.
- GIVEN `agent-browser` is enabled on a host or project WHEN it is invoked for the first time THEN the managed wrapper can install or reuse the real `agent-browser` CLI in host-local user state without requiring Docker.
- GIVEN `agent-browser` is enabled on a host or project WHEN the user runs `agent-browser install` once THEN the browser runtime installs successfully into host-local state under `~/.agent-browser`.
- GIVEN `agent-browser` has been enabled and initialized on a host or project WHEN the user runs a minimal browser flow such as `open`, `wait`, `get title`, and `close` against `https://example.com` THEN the browser session succeeds without a Docker dependency.
- GIVEN `agent-browser` is not explicitly enabled for a host or project WHEN readiness is checked for the ordinary agent baseline THEN absence of `agent-browser` does not count as a readiness failure.

### H: Host/Control-Only Baseline Readiness

The system SHALL keep management-only behavior and credentials out of ordinary targets by default while providing them on the active control host and any explicitly opted-in machines.

**Validation preference:** mixed. Presence of skills/credentials may be smoke-tested; actual control-plane flows are best handled by interactive acceptance.

**Scenarios:**
- GIVEN the general machine is not a management host WHEN it is provisioned THEN it does not need to carry extra management-only SSH private key material by default.
- GIVEN a general machine is not explicitly designated for management work WHEN it is provisioned THEN control-plane VM creation and fleet-administration credentials are not required by default.
- GIVEN a particular target VM needs additional remote-administration capabilities WHEN that target is explicitly configured for them THEN the required credentials and access may be installed as an opt-in extension rather than as the baseline for all general machines.
- GIVEN a user SSHs into the active control host WHEN they start the meta tmux workflow THEN `tmux-meta` starts successfully and provides a local `ctrl` session for control-plane work.
- GIVEN the user is inside `tmux-meta` on the active control host WHEN they inspect the tmux status bar THEN it uses the expected neutral white visual treatment rather than the default tmux green styling.
- GIVEN the user is on the active control host WHEN they invoke the target-entry alias for a configured target THEN the alias SSHes to the target, changes into the configured project repository, and reattaches to an existing `tmux-here` session or creates it if absent.
- GIVEN the user is on the active control host WHEN they need control-plane credentials THEN the host has the required SSH private key material with usable permissions and host configuration needed for remote access.
- GIVEN an agent is running on the active control host WHEN it needs to operate on exe.dev infrastructure THEN it can use the configured SSH and exe.dev access to create VMs and SSH into existing machines for monitoring and updates.
- GIVEN an agent is running on the active control host WHEN it enumerates installed skills THEN the `exe-dev-fleet` skill is available.
- GIVEN an agent is running on the active control host WHEN it invokes the fleet overview workflow THEN it can produce an actual system overview report for reachable exe.dev machines.

### End-To-End Validation Flows

The system SHALL support end-to-end validation flows that exercise the combined `R`, `O`, `A`, and `H` baselines in realistic sessions.

**Validation preference:** interactive acceptance coverage.

**Scenarios:**
- GIVEN a validator SSHs into a general machine WHEN they enter the checked out project repo and run `tmux-here` THEN tmux starts successfully inside the intended project context.
- GIVEN a fresh validation session on the active control host WHEN the user starts `tmux-meta`, enters `~/git/lefant/hackbox-ctrl-inventory`, and launches a `tmux-here` session THEN the nested tmux workflow starts cleanly.
- GIVEN the validation session is active on the active control host WHEN the target-entry alias is used for a configured target THEN tmux capture shows that the session lands in the target project repository inside a reattached-or-created `tmux-here` session.
- GIVEN the fleet skill is available WHEN the overview command is run during validation THEN tmux capture shows non-empty overview output derived from real machine state rather than a placeholder response.

## Open Questions

- [ ] Which exact tmux commands and capture commands should be the canonical validation procedure for proving tmux-meta, tmux-here, and nested tmux behavior?
- [ ] Which specific custom skill, besides `exe-dev-fleet` on the control host, should be the minimum required validation target on ordinary provisioned VMs?
- [ ] Which, if any, ordinary target VMs should opt in to remote-administration credentials beyond the control-host baseline?
- [ ] Should Claude slash-command availability be part of ordinary-machine readiness at all, or treated as a separate optional capability until its ownership model is settled?
