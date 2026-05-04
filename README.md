# Skills Symlink Installation

Install local skills from this repository by symlinking each skill directory from `./skills` into `~/.agents/skills`.

## Assumptions

- A skill is any directory under `./skills` that contains `SKILL.md`.
- Destination directory is `$HOME/.agents/skills`.
- Symlinks are preferred so local edits in this repo are picked up immediately.

## Install (all skills)

```bash
set -euo pipefail

REPO_ROOT="$(pwd)"
SRC_ROOT="$REPO_ROOT/skills"
DST_ROOT="$HOME/.agents/skills"

mkdir -p "$DST_ROOT"

find "$SRC_ROOT" -mindepth 1 -maxdepth 1 -type d | while IFS= read -r skill_dir; do
  [ -f "$skill_dir/SKILL.md" ] || continue
  skill_name="$(basename "$skill_dir")"
  ln -sfn "$skill_dir" "$DST_ROOT/$skill_name"
  echo "linked: $skill_name -> $skill_dir"
done
```

## Install (single skill)

```bash
set -euo pipefail

SKILL_NAME="jakarta-ee-spec-reader"
REPO_ROOT="$(pwd)"
SRC_DIR="$REPO_ROOT/skills/$SKILL_NAME"
DST_ROOT="$HOME/.agents/skills"

[ -f "$SRC_DIR/SKILL.md" ]
mkdir -p "$DST_ROOT"
ln -sfn "$SRC_DIR" "$DST_ROOT/$SKILL_NAME"
```

## Verify

```bash
DST_ROOT="$HOME/.agents/skills"
ls -l "$DST_ROOT"
readlink "$DST_ROOT/jakarta-ee-spec-reader"
```

## Uninstall symlinks

```bash
DST_ROOT="$HOME/.agents/skills"
rm -f "$DST_ROOT/jakarta-ee-spec-reader"
```

To remove all symlinked skills that point into this repo:

```bash
set -euo pipefail

REPO_ROOT="$(pwd)"
DST_ROOT="${CODEX_HOME:-$HOME/.codex}/skills"

find "$DST_ROOT" -mindepth 1 -maxdepth 1 -type l | while IFS= read -r link; do
  target="$(readlink "$link")"
  case "$target" in
    "$REPO_ROOT"/*) rm -f "$link"; echo "removed: $(basename "$link")" ;;
  esac
done
```
