---
name: verify-apache-release
description: Verify integrity of Apache project releases — hash checksums, GPG signatures, KEYS file validation, and Maven staging repository checks. Use when user asks to verify a release, check signatures, confirm hashes, validate a vote, or audit release integrity.
---

# Verify Apache Release

Perform a thorough integrity verification of any Apache project's release candidate. Covers: downloading artifacts, checking SHA1/SHA256/SHA512 hashes, validating GPG signatures against the project's KEYS file, and optionally checking the Maven staging repository.

## Process

### 1. Extract Release Information

From the vote email or announcement, identify:

- **Dist URL** — The staging directory on `dist.apache.org` (typically under `/repos/dist/dev/PROJECT/`)
- **Maven Repo URL** — The staging repository on `repository.apache.org` (optional, but recommended for a complete check)
- **KEYS URL** — Usually `https://dist.apache.org/repos/dist/release/PROJECT/KEYS` (auto-detected from dist URL)
- **Signing key owner** — Who signed the artifacts (e.g., the release manager's Apache UID)

### 2. Run Verification

```bash
SKILL_DIR="$(dirname "$(find_skill_dir verify-apache-release)")"
bash "$SKILL_DIR/scripts/verify-apache-release.sh" <dist-url> [maven-repo-url]
```

The script will:

| # | Step | What it does |
|---|---|---|
| 1 | Fetch KEYS | Downloads the project KEYS file, imports into GPG |
| 2 | Download | Fetches all `.tar.gz` and `.zip` artifacts from the dist directory |
| 3 | Check hashes | Verifies SHA1, SHA256, SHA512 against bundled `.sha*` files |
| 4 | Check signatures | Verifies GPG `.asc` signatures against imported KEYS |
| 5 | Maven (optional) | Samples signed artifacts from the Maven staging repo |

### 3. Interpret Results

| Check | 🔴 Failure means |
|---|---|
| SHA hash mismatch | File was corrupted/tampered — **DO NOT VOTE +1** |
| GPG bad signature | Artifact not signed by a KEYS-file key — **DO NOT VOTE +1** |
| Maven signature invalid | POM/jar in staging repo may be compromised |
| KEYS file unreachable | Cannot verify signing key authenticity |

The GPG warning `"This key is not certified with a trusted signature"` is **normal** — it means only that you haven't personally built a trust path to the key. As long as `"Good signature"` appears and the key is in the official KEYS file, the check passes.

### 4. Additional Manual Checks

- **Tag integrity**: Verify the VCS tag matches the source release artifact
  ```bash
  git tag -v <tag> 2>/dev/null  # if signed
  git diff --stat <tag> -- <extracted-sources>
  ```
- **Cross-repo consistency**: Compare SHA256 of `source-release.zip` between dist and Maven
- **Key freshness**: Check the signing key hasn't expired (the script shows the key ID)
- **Vote thread**: Check other voters' findings on `https://lists.apache.org/`

## Script Usage

```
Usage: verify-apache-release.sh [options] <dist-url> [maven-repo-url]

Arguments:
  <dist-url>         URL to the dist directory on dist.apache.org
  [maven-repo-url]   Maven staging repository URL (optional)

Options:
  -k, --keys <url>         KEYS file URL (default: auto-detected from dist URL)
  -o, --output <dir>       Output directory (default: temp)
  -s, --skip-maven         Skip Maven staging verification
  -g, --maven-group <gid>  Maven group path, e.g. org/apache/tomee (auto-detect)
  -a, --artifact-id <aid>  Maven artifactId, e.g. apache-tomee (auto-detect)
  -V, --maven-version <v>  Maven version override (auto-extracted from dist URL)
  -m, --maven-samples <n>  Max Maven modules to sample (default: 5)
  -v, --verbose            Verbose output
  -h, --help               Show this help
```

## Examples

```bash
# Minimal — dist only, KEYS auto-detected
bash .../verify-apache-release.sh \
  https://dist.apache.org/repos/dist/dev/PROJECT/staging-1234/PROJECT-1.2.3/

# Full — dist + Maven, KEYS and version auto-detected
bash .../verify-apache-release.sh \
  https://dist.apache.org/repos/dist/dev/PROJECT/staging-1234/PROJECT-1.2.3/ \
  https://repository.apache.org/content/repositories/orgapachePROJECT-1234/

# Explicit Maven coordinates (useful when auto-detection fails)
bash .../verify-apache-release.sh \
  --maven-group org/apache/PROJECT \
  --artifact-id PROJECT \
  --maven-version 1.2.3 \
  https://dist.apache.org/repos/dist/dev/PROJECT/staging-1234/PROJECT-1.2.3/ \
  https://repository.apache.org/content/repositories/orgapachePROJECT-1234/

# Custom KEYS URL for non-standard projects
bash .../verify-apache-release.sh \
  -k https://dist.apache.org/repos/dist/release/PROJECT/KEYS \
  https://dist.apache.org/repos/dist/dev/PROJECT/staging-1234/PROJECT-1.2.3/
```

## When Auto-Detection Fails

The script auto-detects three things; you can override each:

| Auto-detection | How it works | Override |
|---|---|---|
| **KEYS URL** | Derives from dist URL path: `/dev/PROJECT/...` → `/release/PROJECT/KEYS` | `-k <url>` |
| **Maven group** | Scans `org/apache/` in the Maven repo, prefers directory matching project name | `-g org/apache/foo` |
| **Maven version** | Extracts from the last path segment of dist URL (finds `X.Y.Z` or `X.Y.Z-QUALIFIER`) | `-V 1.2.3` |
