# Snapshot Strategy

The live backup follows the current state of GitHub. That is useful for fast recovery, but it is not an immutable historical archive.

If a branch is deleted, a tag is removed, history is rewritten or a repository is damaged upstream, a later synchronization can reproduce that state locally.

Filesystem snapshots preserve older generations of the backup.

## Protection layers

```text
GitHub
  |
  v
Live NAS backup
  |
  v
Filesystem snapshots
  |
  v
Independent / off-site copy
```

Each layer protects against a different failure mode.

### Live backup

Protects primarily against:

- repository deletion;
- loss of access to GitHub;
- service-side problems;
- the need for fast local recovery.

### Snapshots

Protect primarily against:

- deleted branches or tags;
- force-push and history rewrite;
- destructive changes already propagated into the live mirror;
- accidental local deletion;
- a bad backup run;
- delayed discovery of corruption.

### Independent copy

Protects against:

- NAS hardware loss;
- storage-pool failure;
- theft;
- fire or flood;
- site-wide failure.

Snapshots stored on the same NAS are not an off-site backup.

## Recommended retention

A balanced GFS-style policy is:

| Snapshot class | Frequency | Retention | Approximate count |
|---|---:|---:|---:|
| Short-term | every 6 hours | 48 hours | 8 |
| Daily | once per day | 14 days | 14 |
| Weekly | once per week | 8 weeks | 8 |
| Monthly | once per month | 12 months | 12 |

This gives dense recovery points near the present and progressively sparser history further back.

## Why 6-hour snapshots for 48 hours?

Most destructive mistakes are noticed quickly:

- accidental branch deletion;
- incorrect force-push;
- bad backup update;
- mistaken repository removal.

Six-hour generations provide good short-term rollback granularity.

## Why 14 daily snapshots?

Not every problem is discovered immediately.

A missing branch, release asset or metadata object may only be noticed several days later.

Two weeks of daily restore points cover this common detection window.

## Why 8 weekly snapshots?

Weekly restore points provide roughly two months of medium-term history.

They are useful when an old branch, release or metadata object is discovered missing weeks after the original event.

## Why 12 monthly snapshots?

Monthly restore points provide useful long-term history without retaining every short-term generation indefinitely.

## Snapshot timing

Prefer snapshots taken after a successful backup run.

A filesystem snapshot can be atomic while the backup process itself is still in the middle of changing:

- Git pack files;
- refs;
- LFS data;
- metadata files.

If the backup runs every 6 hours, schedule snapshots after the expected completion window rather than exactly at backup start.

Where possible, use the successful backup marker as the authoritative signal that a backup cycle finished.

## Recovery objectives

With the default 6-hour backup interval:

```text
Nominal RPO <= 6 hours
```

The local Git mirror usually gives a short RTO for restoring an individual repository.

Restoring a complete GitHub account, including metadata, takes longer and cannot reproduce every GitHub-side attribute exactly.

## Storage behaviour

Copy-on-write snapshots initially consume little extra space because unchanged blocks are shared.

Space usage grows when live data changes.

Git workloads deserve attention because:

- fetches add pack files;
- repacks can rewrite large pack files;
- Git LFS objects can be large;
- release assets and attachments can be large;
- deleting live data does not free blocks still referenced by snapshots.

Monitor real allocated space and free capacity, not only the apparent size of the live backup tree.

## Git garbage collection

A Git repack can rewrite a large amount of data.

With snapshots retained, old pack files may remain referenced while new pack files are written to the live backup.

Therefore:

- avoid unnecessary aggressive `git gc`;
- check free space before bulk maintenance;
- understand that snapshots can retain pre-repack packs;
- expire snapshots according to policy.

## Recovery workflow

When a destructive change is discovered:

1. pause scheduled backup activity if further synchronization could remove useful history;
2. determine approximately when the unwanted change occurred;
3. select the newest snapshot from before the incident;
4. expose or copy the snapshot to a temporary recovery location;
5. run Git integrity checks;
6. create an independent local clone;
7. recover only the required refs or repository when possible;
8. resume scheduled backup only after the desired state is restored.

Do not overwrite the live backup before validating the selected recovery point.

## Verification

Snapshots should be tested, not merely counted.

Recommended baseline:

| Verification | Frequency |
|---|---|
| Git integrity check | weekly |
| Local/offline restore of a rotating repository | weekly |
| Restore from an older snapshot | monthly |
| Broader disaster-recovery exercise | quarterly |

## Extra manual snapshots

Create an additional recovery point before:

- upgrading backup software;
- changing token permissions;
- changing backup flags;
- reorganizing backup storage;
- bulk Git maintenance;
- migrating the storage pool;
- changing retention policy;
- large cleanup operations.

## Policy summary

```text
Backup:
  incremental        every 6 hours
  full metadata      every 7 days

Snapshots:
  short-term         every 6 hours, keep 48 hours
  daily              keep 14 days
  weekly             keep 8 weeks
  monthly            keep 12 months

Verification:
  git fsck           weekly
  local restore      weekly
  snapshot restore   monthly
  broader DR test    quarterly

Off-site:
  maintain an independent copy when the data is important
```

> The live mirror protects against losing the remote source. Snapshots protect against losing yesterday. An independent copy protects against losing the NAS.
