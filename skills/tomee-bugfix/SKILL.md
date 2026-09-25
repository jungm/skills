---
name: tomee-bugfix
description: Fix a bug in Apache TomEE end to end - reproduce it with a failing test, fix it, file the TOMEE Jira issue, open the pull request against apache/tomee, and hand a snapshot build over for verification in the app. Use when the user wants to fix, reproduce, or report a TomEE bug.
---

# TomEE Bugfix

Work through the phases in order. Every phase ends at a **gate**: stop, show the user what the phase produced, and wait for an explicit go-ahead before starting the next phase. A go-ahead covers only the phase it was given for. When the user asks for several phases in one message, still stop at each gate in between.

The checkout lives at `~/Projects/tomee`. Remotes: `origin` is `apache/tomee`, `jungm` is the user's fork.

## 1. Checkout

Run `git status`, `git branch --show-current`, and `git fetch origin`.

Done when the working tree is clean and on `main`, or the user has said how to handle what is there.

**Gate:** report branch, cleanliness, and how far `main` is behind `origin/main`.

## 2. Reproduce

Write a test that goes **red** on the bug, in the module that owns the behaviour (for container features, the matching `arquillian/arquillian-tomee-tests/*` module when the bug needs a running container). Follow the neighbouring tests' style; embed XML descriptors (`persistence.xml`, `beans.xml`, ...) as Java text blocks.

Run it and read the failure. Done when the test fails with the exact error the bug produces, not a setup or dependency error, and the module's existing tests still pass.

**Gate:** show the test and the failure output.

## 3. Fix

Change the smallest amount of production code that turns the test **green**. Comments describe the code as it is; the history belongs in the commit message.

Build the fixed module with `mvn install` before running an arquillian test module, which resolves it from `~/.m2`. Then run: the new test, the rest of its test module, and the fixed module's own tests.

Done when all three are green.

**Gate:** show the diff and the test results. Mention that `mvn install` replaced the module's `11.0.0-SNAPSHOT` jar in `~/.m2`.

## 4. Jira

Draft the issue for project `TOMEE`, type Bug. Keep it short: what the code does, why that is wrong, the resulting error, and the direction of the fix. When a Jakarta EE spec is the reason, cite the section with the `jakarta-ee-spec-reader` skill: spec name, version, section number and title, the published link with its anchor, and a short quote.

**Gate:** show the draft. Create it with `mcp__asf-jira__jira_create_issue` only after the go-ahead.

## 5. Pull request

Prepare, but do not run yet:

- Branch named after the Jira key (`TOMEE-1234`), created from the latest `origin/main`.
- Commit message `TOMEE-1234 <what the change does, lowercase>`.
- Push to the `jungm` remote.
- PR against `apache/tomee` `main`, titled `TOMEE-1234 - <what the change does>`. The body links the Jira issue, explains why the old code was wrong and what changed, and states the test evidence (red without the fix, green with it). Match the user's recent merged PRs: `gh pr list -R apache/tomee --author jungm --state merged`.

**Gate:** show branch name, commit message, and PR title and body. On the go-ahead, commit, push, and run `gh pr create`.

## 6. Jira fields

Propose:

- **Affects Version:** the released versions whose tag contains the buggy code. Check with `git grep <symbol> <tag> -- <path>` against `tomee-project-*` tags.
- **Fix Version:** the next unreleased version on that line, from `mcp__asf-jira__jira_get_project_versions`.
- **Assignee:** the user.

**Gate:** show the proposed values, then set them with `mcp__asf-jira__jira_update_issue` (`versions`, `fixVersions` by id) and `mcp__asf-jira__jira_assign_issue`.

## 7. Integrate the snapshot

Run this phase when the bug came from an application. The user verifies it end to end; this phase prepares that.

Build a snapshot from the fix branch. Build only what the app consumes, with its reactor dependencies: read the app's `pom.xml` for the TomEE artifacts it uses (BOM, `tomee-embedded-maven-plugin` or `tomee-maven-plugin` and their plugin dependencies), find each module's path in the TomEE tree, and run `mvn install -DskipTests -Dcheckstyle.skip -pl <paths> -am` in the background. Point the app's `tomee.version` at the snapshot (`11.0.0-SNAPSHOT`) and compile it.

Done when the snapshot is integrated into the project: installed, `tomee.version` pointing at it, and the app compiling against it. The user runs the app and verifies the fix; start the app only when the user asks for it.

**Gate:** hand off to the user with what to check. Include the command that starts the app (offline, `mvn -o`, so the local snapshot wins over a newer nightly; an IDE run with `--update-snapshots` replaces it once one is published), the steps that used to trigger the bug, the log line or behaviour that shows it is gone, and the previous `tomee.version` so the user can switch back. The app changes stay uncommitted.

## Gotchas

- `mvn -o` fails on snapshot poms that were never downloaded. Run the first build of a module online.
- ASF Jira is Jira Server: the Markdown `>` blockquote reaches it unconverted. Write quotes as `bq. ` paragraphs.
- `jira_assign_issue` does not resolve the username `jungm`; pass the display name `Markus Jung`.
