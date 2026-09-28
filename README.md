# GitHub to NAS Backup

Generic Docker-based backup of a GitHub user or organization to local NAS storage.

The project uses `josegonzalez/python-github-backup` and is designed to preserve both Git data and GitHub-side metadata.

## What is backed up

The default configuration includes:

- public repositories
- private repositories visible to the token
- forks
- full Git mirrors
- all refs
- Git LFS objects
- wikis
- Issues, comments, events and timelines
- Pull Requests, reviews, comments and commits
- labels and milestones
- Discussions
- Releases and release assets
- attachments where GitHub permits access

The upstream `--bare` option creates a real Git mirror using `git clone --mirror`.

## Protection model

```text
GitHub
   |
   | pull backup
   v
Local NAS backup
   |
   +-- Git mirrors
   +-- Git LFS
   +-- GitHub metadata
   |
   v
Filesystem snapshots
   |
   v
Optional off-site backup
```

The live backup protects against losing GitHub data. Snapshots preserve older states after deletions or history rewrites propagate into the mirror. An independent copy protects against loss of the NAS itself.

## Files

```text
compose.yaml
backup-loop.sh
verify-backups.sh
.env.example
.gitignore
docs/
  RESTORE-TEST.md
  SNAPSHOT-STRATEGY.md
```

## Quick start

Copy the environment template:

```bash
cp .env.example .env
```

Edit `.env` and provide:

- the GitHub user or organization
- whether the target is an organization (`GH_ORGANIZATION=true`)
- an absolute NAS path for backup data
- optional timezone and scheduling intervals

Create the token secret:

```bash
mkdir -p secrets
printf '%s\n' 'YOUR_GITHUB_TOKEN' > secrets/github_token
chmod 600 secrets/github_token
```

Use a read-only fine-grained Personal Access Token where possible. Typical permissions are read access to Contents, Metadata, Issues, Pull Requests and Discussions.

Start the service:

```bash
docker compose config
docker compose pull
docker compose up -d
```

Follow logs:

```bash
docker compose logs -f github-backup
```

## Optional success keepalive

An optional HTTP GET notification can be sent after a backup finishes successfully.

Configure it in `.env`:

```dotenv
KEEPALIVE_URL=https://example.invalid/your-monitoring-endpoint
KEEPALIVE_TIMEOUT=10
```

Leave `KEEPALIVE_URL` empty to disable the feature.

The URL is called only after:

1. `github-backup` exits successfully;
2. the local success marker is updated;
3. any previous failure marker is removed;
4. the full-backup marker is updated when applicable.

If the backup fails, the keepalive URL is **not called**.

If the backup succeeds but the keepalive endpoint itself fails or times out, the backup remains successful and the notification failure is logged as a warning. The URL itself is not written to the log.

This makes the option suitable for success-ping services such as self-hosted monitoring endpoints or health-check systems.

## Default schedule

```text
Incremental backup: every 6 hours
Full metadata refresh: every 7 days
```

The first run is full.

The wrapper records:

```text
status/last-full
status/last-success
status/last-failure
```

These files can be monitored externally.

## Verification

Run:

```bash
BACKUP_ROOT=/path/to/backup/storage sh ./verify-backups.sh
```

This runs `git fsck --full` against every repository mirror found in the backup.

A stronger restore test is documented in [docs/RESTORE-TEST.md](docs/RESTORE-TEST.md).

## Snapshots

Recommended baseline:

| Class | Frequency | Retention |
|---|---:|---:|
| Short-term | every 6 hours | 48 hours |
| Daily | once per day | 14 days |
| Weekly | once per week | 8 weeks |
| Monthly | once per month | 12 months |

See [docs/SNAPSHOT-STRATEGY.md](docs/SNAPSHOT-STRATEGY.md).

## Important limitation

Git repositories can be restored directly.

GitHub metadata such as Issues, Pull Requests and Discussions is primarily an archive. GitHub APIs do not allow exact recreation of original numbers, authors, timestamps and every relationship.

## Disaster-recovery rule

A backup is not considered verified merely because the backup command succeeded.

It is verified when useful data can be reconstructed from the local copy without contacting GitHub.
