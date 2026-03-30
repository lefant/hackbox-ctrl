---
date: 2026-03-27
topic: "State backups for exe.dev VMs with restic, GCS, Pulumi-managed cloud setup, and system-level Nix"
tags: [research, backups, exe-dev, restic, gcs, pulumi, nix, systemd]
---

# State Backups For exe.dev VMs With restic, GCS, Pulumi-Managed Cloud Setup, And System-Level Nix

## Purpose

Record the current implementation-oriented design considerations for backing up **stateful, non-git-tracked data** on exe.dev VMs.

Primary targets:

- OpenClaw-style persistent memory/state
- Minecraft server world state
- Docker bind mounts and durable named volumes
- optional non-throwaway databases

This note is **not** about raw VM image backup. It is about preserving the small set of durable paths that matter when a VM is rebuilt.

## Current goal

The restore model we want is:

1. create or reprovision a fresh exe.dev VM
2. reinstall the runtime stack and baseline tools
3. restore persistent state directories
4. restart services

That matches the current exe.dev usage much better than whole-machine imaging.

## Relevant exe.dev constraints

From exe.dev docs and the current repo workflow:

- exe.dev VMs are normal Linux VMs with **persistent disks**
- all management is via **SSH**
- direct SSH to `<vm>.exe.xyz` supports normal shell, `scp`, and normal Linux tooling patterns
- Docker is supported because the VM is effectively "just a VM"
- this repo already provisions exe.dev VMs over SSH and places credentials/material on targets during provisioning

Implications:

- there is no special exe.dev-native backup primitive in current use here
- backup should be treated like backup on any Linux host
- running backup locally on the VM is natural
- the control host can still orchestrate installation, triggering, and status collection over SSH

## What should be backed up

For the current fleet shape, the priority is **state**, not machine images.

Good backup candidates:

- service state under explicit paths such as `/srv/<service>`
- selected config under `/etc/<service>`
- Docker bind-mounted data directories
- named Docker volumes that contain durable application data
- Minecraft worlds, plugin data, and server config
- OpenClaw or similar durable memory/state directories
- database dumps for services that stop being throwaway

Usually not worth backing up:

- git clones
- package installs
- Nix store contents
- caches
- build artifacts
- Docker images and container layers
- most logs
- ephemeral development databases

## Filesystem convention that would simplify backups

The simplest long-term fleet convention is:

- `/srv/<service>` = durable mutable state
- `/etc/<service>` = durable host/service config
- everything else is disposable unless explicitly opted in

Examples:

- `/srv/minecraft`
- `/srv/openclaw`
- `/srv/n8n`
- `/srv/<other-app>`

This is especially useful for Docker workloads. Prefer bind mounts into `/srv/...` over opaque named volumes whenever possible.

## Tooling choice

### restic

`restic` remains the leading candidate because it provides:

- encrypted backups
- incremental snapshots
- deduplication
- retention policies
- straightforward restore of specific paths
- first-class GCS backend support via `gs:` repositories

That fits Minecraft worlds, app state directories, and occasional database dumps well.

### Why not plain `rclone sync`

Plain `rclone sync` to object storage is simpler, but it loses the main benefits we want:

- snapshot history
- point-in-time restore
- retention pruning
- nicer restore workflow

### Current recommendation

Prefer **restic** as the backup engine.

## Additional restic security findings

A few restic documentation points materially affect the design:

- restic explicitly states it is **not designed to protect against attackers deleting files at the storage location**
- if **multiple hosts write to the same repository**, a leaked repository key/password allows decryption of backup data for **every host using that repository**
- with append-only repositories, restic documents specific retention caveats and recommends **time-based `--keep-within*` policies** over purely count-based retention when security matters
- `prune` is the operation that actually removes unreferenced data, and it can be disruptive enough that its scheduling matters separately from ordinary backups

Implication:

- per-VM isolation should be treated as a **repository boundary**, not just as a naming convention
- one shared restic repository for many VMs is a poor security boundary
- backup retention and deletion authority should be designed intentionally, not treated as an afterthought

## GCS backend details

Current restic docs indicate that Google Cloud Storage is a supported backend using the `gs:` repository type.

Relevant restic backend details:

- repository syntax: `gs:<bucket>:/<optional-path>`
- example init form: `restic -r gs:<bucket>:/ init`
- typical environment variables:
  - `GOOGLE_PROJECT_ID`
  - `GOOGLE_APPLICATION_CREDENTIALS`
  - `RESTIC_REPOSITORY`
  - `RESTIC_PASSWORD_FILE`
- `GOOGLE_ACCESS_TOKEN` is also supported, but restic docs note that access tokens are short-lived and are therefore a poor fit for unattended scheduled backups

The restic docs also state that normal operation requires object permissions equivalent to:

- `storage.objects.create`
- `storage.objects.delete`
- `storage.objects.get`
- `storage.objects.list`

The docs call out that these are included in the **Storage Object Admin** role.

If the backup process must create the bucket, additional bucket-creation permission is required:

- `storage.buckets.create`

The docs note that this is included in the **Storage Admin** role. If the bucket already exists, that extra permission is unnecessary.

The restic `latest` docs also mention a few backend tuning details for GCS:

- concurrent GCS connections can be tuned with `-o gs.connections=10`
- bucket-creation region can be specified via backend options when restic is creating the bucket

## Credential model for exe.dev VMs

Because exe.dev VMs are not Google-managed compute instances, the realistic first-version credential model is:

1. create a Google Cloud service account
2. grant it least-privilege access to the backup bucket
3. create a JSON service account key
4. place that key on the VM at a protected path
5. set restic/GCS environment variables on the VM

### Required secrets and config on the VM

A working restic-to-GCS VM needs at least:

- **GCS service account JSON key**
  - example path: `/var/lib/hackbox-backup/credentials/gcs-service-account.json`
- **restic repository password file**
  - example path: `/var/lib/hackbox-backup/credentials/restic-password`
- **Google project ID**
- **restic repository URL**
  - example: `gs:exe-dev-state-backups:/lefant-memory`

### Example environment file

Example runtime env file:

```sh
GOOGLE_PROJECT_ID=my-gcp-project
GOOGLE_APPLICATION_CREDENTIALS=/var/lib/hackbox-backup/credentials/gcs-service-account.json
RESTIC_REPOSITORY=gs:exe-dev-state-backups:/lefant-memory
RESTIC_PASSWORD_FILE=/var/lib/hackbox-backup/credentials/restic-password
```

### Operational caveat

A long-lived JSON service account key is operationally simple, but it is also a sensitive static credential. If used, it should be:

- scoped narrowly to the backup bucket or repository boundary
- readable only by root or the dedicated backup user
- stored outside git
- rotated if exposure is suspected
- copied only to VMs that actually perform backups

### Repository password and service-account scope both matter

restic uses both:

- storage credentials, which control who can access the backend objects
- a repository password/key, which controls who can decrypt the repository contents

This means the effective security boundary is not just "which GCS key is on the VM". It is also:

- which restic repository that VM can reach
- whether that repository password is shared with other hosts

If multiple VMs share the same repository and password, compromise of one VM can expose the backup contents of the others.

### Best-practice implication

The safest default is:

- **one restic repository per VM**
- **one repository password per VM**
- **one GCS service account per VM**

That aligns the cryptographic boundary, the cloud IAM boundary, and the operational restore boundary.

### Why not other GCP auth modes?

Possible alternatives exist, but they are less natural for exe.dev:

- **short-lived access token**
  - not good for unattended recurring backups
- **ambient Application Default Credentials from cloud instance metadata**
  - unlikely on exe.dev VMs
- **service account impersonation from another trusted machine**
  - possible, but more complex than needed for a first version

## Where should restic run?

This remains the main architecture choice.

### Option A: run restic on each VM

The VM itself runs backup commands on a schedule and writes directly to GCS.

Typical flow:

1. optional pre-hook quiesces a service
2. restic backs up local state paths
3. optional post-hook resumes service
4. retention pruning runs
5. logs and metadata are written locally and can be inspected remotely

Advantages:

- the VM has direct access to local files and Docker volumes
- easier to quiesce services locally
- backup continues even if the control host is offline
- no large state transfer through the control host
- scales naturally with the fleet

Costs:

- GCS credentials must be distributed to backup-enabled VMs
- per-VM scheduling and monitoring must exist
- operational visibility must be collected rather than being inherently centralized

### Option B: run backups from the control host over SSH

The control host orchestrates backup by SSHing into a VM and either triggering remote commands or streaming data back.

Advantages:

- cloud credentials can remain centralized
- one place to trigger and inspect backup runs
- target VMs would not need direct bucket access

Costs:

- the control host becomes a dependency for all backups
- streaming large datasets over SSH is slower and more failure-prone
- service quiescing is less elegant
- control-host outages delay all backups
- data takes an unnecessary network hop

### Current recommendation

For this fleet shape, the best default is:

- **run restic on each VM**
- optionally let the control host **install, trigger, and monitor** those backups over SSH

In short:

- **execution and scheduling live on the VM**
- **fleet orchestration can still live on the control host**

## Scheduling: systemd timer on the VM

This can now be specified in more detail.

### Current recommendation

Use a **system-level `systemd` service + timer** on each backup-enabled VM.

Not Home Manager user services. Not repo-local `devenv` process definitions.

Reasoning:

- this is a whole-VM operational responsibility, not user dotfile state
- it should survive shell/session churn
- it should not require an active login session
- it should be managed the same way as other machine services

### Why system-level timer instead of Home Manager timer?

A user-level timer can work only if user services are guaranteed to be active in the background, usually via lingering or a continuously active login/session manager.

That is an unnecessary dependency here.

A system-level timer is simpler and more explicit for a VM backup job:

- runs independently of interactive login
- easier to audit with `systemctl status`
- naturally owns privileged paths and credentials under `/etc` or `/var/lib`
- cleaner fit for root-owned service quiesce hooks if needed

### Proposed unit structure

Suggested files:

- `/etc/systemd/system/hackbox-backup@.service`
- `/etc/systemd/system/hackbox-backup@.timer`
- `/etc/hackbox-backup/<name>.env`
- `/etc/hackbox-backup/<name>.paths`
- optional hook scripts under `/usr/local/libexec/hackbox-backup/`

Where `<name>` is a target backup profile, usually one per VM at first.

### Proposed service behaviour

The service should:

1. load the env file for repository + credential paths
2. run optional pre-hook
3. validate included paths exist where appropriate
4. run `restic backup` for the configured paths
5. write/update a local success marker on success
6. run retention with `restic forget ...`
7. run optional post-hook in a trap/finalizer style so quiesced services are resumed

### Important restic scheduling detail: prune is special

restic documentation notes that:

- `forget` marks snapshots for removal according to policy
- `prune` is what removes unreferenced data
- during `prune`, the repository is locked and backups cannot complete

Implication:

- a first version should consider **separating backup runs from prune runs**
- frequent backups can run on a short schedule
- prune can run less often, for example daily or weekly, during a quieter window

This is especially relevant if repositories become large or if backup windows overlap.

### Proposed timer behaviour

Reasonable first version:

- `OnCalendar=hourly` or `OnCalendar=*:0/6`
- `Persistent=true`

`Persistent=true` matters so missed timer runs happen after reboot.

### Suggested first retention policy

A practical starting point for ordinary non-append-only repositories:

- keep 7 daily
- keep 4 weekly
- keep 12 monthly

### Append-only retention caveat from restic docs

restic specifically warns that append-only repositories have security considerations when using policy-based snapshot removal.

The docs' TL;DR is that in append-only mode one should prefer **time-based retention** using `--keep-within*` options, for example:

- `--keep-within 7d`
- `--keep-within-daily 7d`
- `--keep-within-weekly 1m`
- `--keep-within-monthly 1y`

The reason is that count-based retention such as `--keep-daily 7` can be manipulated more easily by an attacker who can create many snapshots and push legitimate snapshots out of the retained set.

Implication:

- if we pursue append-only or deletion-restricted designs, retention should be revisited and likely moved to `--keep-within*` semantics
- count-based retention is acceptable for a simpler normal-writer model, but it is not the best security pattern for append-only scenarios

## Nix ownership model

This is now clearer.

### Current recommendation

Manage backup installation and service wiring through **system-level Nix**, not Home Manager and not repo-local `devenv`.

This is a machine concern.

### What system-level Nix should own

Good fit for a NixOS module or host-level Nix definition:

- install `restic`
- install helper scripts
- render systemd service/timer units
- render static backup configuration files
- declare directories like `/etc/hackbox-backup` and `/var/lib/hackbox-backup`
- enable/disable backup profiles per host

### What should remain out-of-band from pure Nix store content

Secrets should not live in the Nix store.

So even if Nix owns the service definitions, these still need an out-of-band secret placement path:

- GCS service account JSON key
- restic password file
- any hook credentials

### Fit with current repo direction

This repo already provisions exe.dev VMs over SSH and copies secrets/material from gitignored `credentials/` inputs.

That means a realistic split is:

- **Nix** owns packages, unit files, wrapper scripts, and static config shape
- **inventory credentials** own actual secret material copied onto the VM

## Inventory configuration shape

You noted that `targets/` may eventually be replaced, but a starter layout should work now.

### Recommendation

Use a **dedicated backup config file per target**, rather than stuffing too many backup-specific fields into `targets/<fqdn>/config.env`.

That keeps backup policy separate from general provisioning metadata.

### Suggested location

For now:

- `targets/<fqdn>/backup.env`

or, if multi-profile backups become likely:

- `targets/<fqdn>/backup/<profile>.env`

The simplest v1 is probably:

- `targets/<fqdn>/backup.env`

### Why a dedicated file is better

Benefits:

- avoids overloading provisioning metadata
- easier to replace later if inventory format changes
- isolates backup policy from general target shape
- easier to parse and validate independently

### Proposed `backup.env` fields

A practical first pass:

```sh
BACKUP_ENABLED=1
BACKUP_PROFILE=default
BACKUP_SCHEDULE=hourly
BACKUP_REPOSITORY=gs:exe-dev-state-backups:/lefant-memory
BACKUP_GOOGLE_PROJECT_ID=my-gcp-project
BACKUP_PATHS="/srv/openclaw /etc/openclaw"
BACKUP_EXCLUDES="/srv/openclaw/tmp /srv/openclaw/cache"
BACKUP_PRE_HOOK=/usr/local/libexec/hackbox-backup/pre-default.sh
BACKUP_POST_HOOK=/usr/local/libexec/hackbox-backup/post-default.sh
BACKUP_RETENTION_DAILY=7
BACKUP_RETENTION_WEEKLY=4
BACKUP_RETENTION_MONTHLY=12
BACKUP_REQUIRES_DOCKER=0
```

### Better shape for path lists

If quoting becomes awkward, split them into sidecar files:

- `targets/<fqdn>/backup.paths`
- `targets/<fqdn>/backup.excludes`

That is probably easier than forcing shell-safe multi-path values into one env line.

A strong v1 layout could be:

- `targets/<fqdn>/backup.env`
- `targets/<fqdn>/backup.paths`
- optional `targets/<fqdn>/backup.excludes`

## Proposed VM-side filesystem layout

A concrete VM layout would help standardize implementation.

### Config and credentials

- `/etc/hackbox-backup/<profile>.env`
- `/etc/hackbox-backup/<profile>.paths`
- `/etc/hackbox-backup/<profile>.excludes`
- `/var/lib/hackbox-backup/credentials/gcs-service-account.json`
- `/var/lib/hackbox-backup/credentials/restic-password`

### Runtime metadata

- `/var/lib/hackbox-backup/state/<profile>.last-success`
- `/var/lib/hackbox-backup/state/<profile>.last-failure`
- `/var/log/hackbox-backup/<profile>.log` or journal-only logging

### Hooks

- `/usr/local/libexec/hackbox-backup/pre-<profile>.sh`
- `/usr/local/libexec/hackbox-backup/post-<profile>.sh`

## Example backup wrapper shape

A wrapper script such as `/usr/local/libexec/hackbox-backup/run-profile` could:

```sh
#!/usr/bin/env bash
set -euo pipefail

profile="${1:?profile required}"
env_file="/etc/hackbox-backup/${profile}.env"
paths_file="/etc/hackbox-backup/${profile}.paths"
excludes_file="/etc/hackbox-backup/${profile}.excludes"

set -a
. "$env_file"
set +a

pre_hook="${BACKUP_PRE_HOOK:-}"
post_hook="${BACKUP_POST_HOOK:-}"

cleanup() {
  if [ -n "$post_hook" ] && [ -x "$post_hook" ]; then
    "$post_hook"
  fi
}
trap cleanup EXIT

if [ -n "$pre_hook" ] && [ -x "$pre_hook" ]; then
  "$pre_hook"
fi

mapfile -t paths < "$paths_file"
restic backup --files-from "$paths_file" ${BACKUP_EXCLUDES_FILE:+--exclude-file "$excludes_file"}
restic forget --prune \
  --keep-daily "${BACKUP_RETENTION_DAILY:-7}" \
  --keep-weekly "${BACKUP_RETENTION_WEEKLY:-4}" \
  --keep-monthly "${BACKUP_RETENTION_MONTHLY:-12}"
```

The final implementation would need a bit more shell-hardening than that, but this is the operational shape.

## Repository verification practices from restic docs

restic documentation recommends running `restic check` regularly to verify repository integrity.

Additional useful guidance:

- `restic check` verifies repository structure and metadata
- `restic check --read-data` or `--read-data-subset` provides a stronger verification pass by actually reading backup data
- after prune, running `restic check` is explicitly advisable

Implication for this design:

- a lightweight `restic check` should likely be part of normal maintenance
- a heavier `restic check --read-data-subset` or occasional `--read-data` run should be scheduled separately, less frequently
- prune jobs should probably be followed by an integrity check step or a separately scheduled verification window

## Service-specific consistency details

### Minecraft

Minecraft world data should not be copied mid-write without some care.

Safer patterns:

- stop the server briefly before backup, or
- use save controls such as `save-all`, `save-off`, backup, then `save-on`

If downtime is acceptable, a short stop is the simplest and safest option.

Example pre/post hook model:

- pre-hook: send `save-all`, then `save-off`
- post-hook: send `save-on`

Or simply:

- pre-hook: stop service/container
- post-hook: start service/container

### OpenClaw / memory-style services

The key question is where durable memory is actually stored.

Candidates:

- SQLite files
- JSON or flat-file state
- embedded vector-store files
- uploaded blobs

If the app has a proper export or quiesce path, use it. Otherwise, a brief service stop may be safer than copying actively mutating files.

### Docker state

Do not back up containers themselves.

Back up instead:

- bind-mounted state directories
- selected named volumes
- compose files and host config if not otherwise tracked

Future preference remains:

- put durable state in bind mounts under `/srv/<service>`

### Databases

For throwaway dev databases, default to not backing them up.

If a DB becomes important, switch to logical dumps:

- Postgres: `pg_dump` or `pg_dumpall`
- MySQL/MariaDB: `mysqldump`
- SQLite: `.backup` or careful copy while quiesced

Store dumps in an explicit path such as `/var/backups/<service>` and include that path in restic.

## GCS bucket/repository layout

After reviewing the restic security model more closely, the stronger recommendation is:

- **one restic repository per VM**
- preferably **one GCS bucket per VM** when we want the cleanest IAM isolation

Examples:

- `gs:exe-dev-backup-lefant-memory:/`
- `gs:exe-dev-backup-minecraft-1:/`
- `gs:exe-dev-backup-altego-agent-now:/`

This gives:

- clean per-VM IAM boundaries
- clean per-VM repository-password boundaries
- per-VM restore clarity
- less chance of cross-VM mistakes
- lower blast radius if one VM is compromised

### Shared bucket with prefixes is still possible, but weaker

A shared bucket with one prefix/repository per VM is still operationally possible, but it is a weaker and easier-to-misconfigure isolation model.

If the goal is specifically to prevent one VM from being able to delete or decrypt all other backups, then:

- one shared bucket is not the cleanest trust boundary
- one bucket per VM is easier to reason about

## Required cloud infrastructure

You specifically asked for required credentials in detail and suggested Pulumi. That looks like the right direction.

### Cloud resources needed

Minimum GCP infrastructure for v1:

1. a GCP project
2. a dedicated GCS bucket for each backup-enabled VM, or a consciously accepted weaker shared-bucket design
3. one or more service accounts for restic writers
4. IAM bindings allowing those service accounts to access only their intended bucket or repository boundary
5. optional bucket settings such as:
   - versioning
   - lifecycle rules
   - uniform bucket-level access
   - storage class / location selection

### Suggested IAM stance

For the backup writer service account:

- grant only the bucket access needed for restic object operations
- do not grant broad project-wide admin where avoidable
- align the IAM boundary with the restic repository boundary whenever possible

At a high level, the service account needs to be able to read/list/write/delete objects in the bucket used by its repository.

If we want to avoid one VM being able to delete every other VM's backups, the cleanest model is:

- one service account per VM
- one bucket per VM
- one restic repository and password per VM

### Pulumi is a good fit

Pulumi GCP docs indicate straightforward support for:

- `gcp.storage.Bucket`
- service account resources
- bucket IAM membership resources
- service account key resources

So a Pulumi stack can manage:

- bucket creation
- bucket settings
- service accounts
- bucket-level IAM grants
- optional generation of service account keys

## Proposed Pulumi stack shape

This should be documented as a starter spec even before implementation.

### Suggested repo location

If managed from this inventory for now, likely under something like:

- `infra/pulumi/gcp-backups/`

or in shared utils later if it becomes generic.

### Suggested Pulumi stack responsibilities

A `gcp-backups` stack should manage:

- backup buckets
- bucket configuration
- ideally one service account per VM
- IAM bindings from each service account to its bucket
- optional export of key material as encrypted Pulumi secrets

### Suggested outputs

Per VM/profile, outputs could include:

- bucket name
- repository prefix
- service account email
- generated key JSON as a secret output if this path is chosen
- recommended `RESTIC_REPOSITORY` string
- `GOOGLE_PROJECT_ID`

### Example conceptual Pulumi resource set

Conceptually:

- `gcp.storage.Bucket("exe-dev-backup-lefant-memory", ...)`
- `gcp.serviceaccount.Account("restic-lefant-memory", ...)`
- `gcp.storage.BucketIAMMember(...)`
- `gcp.serviceaccount.Key(...)`

### Security caveat for Pulumi-managed keys

If Pulumi generates service account keys, those keys become highly sensitive outputs.

That is workable only if:

- the Pulumi state backend is secured
- secret outputs are encrypted
- the operational flow for copying those secrets into `credentials/` is explicit and careful

A safer operational variant is:

- Pulumi manages bucket + service account + IAM
- key generation/export is done in a tightly controlled step outside broad automation

This trade-off should be decided explicitly during implementation.

## Per-VM service account vs shared service account

You asked for at least a quick check here.

### Best-practice preference

**One service account per VM** is the cleaner cloud-IAM security boundary.

Pros:

- easier key rotation per VM
- easier incident isolation
- easier revocation for one compromised host
- clearer audit trail over time

But restic docs push this one step further: the safest real boundary is achieved when we also use:

- one repository per VM
- one repository password per VM
- ideally one bucket per VM

### Acceptable simplification for early rollout

A **small shared service account** for several low-risk VMs is operationally simpler and may be acceptable for a first pass.

Costs:

- one key compromise affects multiple VMs
- revoking one host becomes harder
- audit boundaries are weaker

### Current recommendation

Preferred:

- **one service account per backup-enabled VM**

Acceptable temporary compromise:

- one service account per backup risk class or per environment group

For example:

- one for personal low-risk VMs
- one for more sensitive memory/state VMs

## Concrete implementation shape for this repo

A practical v1 in this repo could look like:

### Inventory inputs

Per target:

- `targets/<fqdn>/backup.env`
- `targets/<fqdn>/backup.paths`
- optional `targets/<fqdn>/backup.excludes`
- optional hook scripts in a future dedicated directory or rendered from templates

### Credentials inputs

Gitignored:

- `credentials/targets/<fqdn>/gcs-service-account.json`
- `credentials/targets/<fqdn>/restic-password`

or shared if intentionally reused:

- `credentials/shared/gcs/<name>.json`
- `credentials/shared/restic/<name>.password`

### VM placement

Installed during provisioning or reconciliation:

- `/etc/hackbox-backup/*.env`
- `/etc/hackbox-backup/*.paths`
- `/etc/hackbox-backup/*.excludes`
- `/var/lib/hackbox-backup/credentials/*`
- `/etc/systemd/system/hackbox-backup@.service`
- `/etc/systemd/system/hackbox-backup@.timer`
- `/usr/local/libexec/hackbox-backup/*`

### Control-host responsibilities

The control host can still provide:

- install/reconcile command for backup config
- fleet status command
- ad hoc trigger command
- restore helper docs and wrappers

## Suggested next implementation step

The next document should probably be a concrete design/spec that defines:

1. exact backup inventory schema and file names
2. exact VM filesystem paths
3. exact systemd service/timer unit contents
4. exact secret placement flow
5. exact Pulumi stack shape for GCS bucket + IAM + service accounts
6. whether service account keys are generated inside Pulumi or out-of-band

## Current recommendation summary

The strongest current v1 recommendation is:

1. **Backup engine:** `restic`
2. **Storage backend:** GCS
3. **Execution model:** restic runs on each VM
4. **Scheduling:** system-level `systemd` timer on each VM
5. **Ownership:** system-level Nix, not Home Manager and not `devenv`
6. **Inventory config:** dedicated backup files under each target, not just more fields in `config.env`
7. **Secrets:** gitignored credentials placed onto the VM out-of-band
8. **Cloud setup:** managed by a Pulumi GCP stack
9. **Security boundary:** ideally one service account per VM, one repository per VM, one repository password per VM, and preferably one bucket per VM
10. **Maintenance model:** consider separating frequent backup runs from less frequent prune and verification runs
11. **Verification:** run `restic check` regularly and schedule periodic deeper verification with `check --read-data-subset` or `check --read-data`

## References

- exe.dev docs index: `https://exe.dev/docs.md`
- exe.dev docs (all): `https://exe.dev/docs/all.md`
- restic docs, preparing a repository: `https://restic.readthedocs.io/en/stable/030_preparing_a_new_repo.html`
- restic docs, backup/env vars: `https://restic.readthedocs.io/en/stable/040_backup.html`
- Google Cloud Storage authentication docs: `https://cloud.google.com/storage/docs/authentication`
- Pulumi GCP docs/context for storage buckets, service accounts, keys, and IAM bindings
- `tooling/hackbox-ctrl-utils/scripts/provision-exe-dev-nix.sh`
- `tooling/hackbox-ctrl-utils/docs/research/2026-03-25-home-manager-shared-conventions-and-devenv-boundaries.md`
- `tooling/hackbox-ctrl-utils/docs/research/2026-03-26-updated-scope-classification-and-shared-nix-layering.md`
