---
name: tomee-dependabot
description: Triage and merge the open Dependabot PRs on apache/tomee - classify each PR, decide which get a TOMEE Jira issue, close the ones that break the build or the Jakarta EE line, and squash merge the rest. Use when the user asks about dependabot PRs, dependency bump PRs, or wants them merged.
---

# TomEE Dependabot

Work through the phases in order. Every phase ends at a **gate**: stop, show the user what the phase produced, and wait for an explicit go-ahead. Writes to GitHub or Jira (closing, renaming, merging, creating or editing issues) happen only in phase 4.

The checkout lives at `~/Projects/tomee`. Remotes: `origin` is `apache/tomee`, `jungm` is the user's fork. Pass `-R apache/tomee` to every `gh` call.

## The Jakarta EE line guardrail

Each branch ships exactly one Jakarta EE version, and each EE implementation has a release line bound to that version. A bump that moves an implementation onto another line silently mixes EE versions in the distribution: it compiles, CI goes green, and the server ships a component built for the wrong spec. **Merge only bumps that stay on the branch's line.**

Derive the branch's EE version from its project version (`git show origin/<branch>:pom.xml`): TomEE 11 is Jakarta EE 11, TomEE 10 is Jakarta EE 10. The lines as of TomEE 11.0.0 / 10.3.0:

| Component | TomEE 11 (main) | TomEE 10 (tomee-10.x) |
|---|---|---|
| Tomcat | 11.0.x | 10.1.x |
| MyFaces | 4.1.x | 4.0.x |
| Mojarra (`org.glassfish:jakarta.faces`) | 4.1.x | 4.0.x |
| ActiveMQ | 6.3.x | 6.3.x (see below) |

ActiveMQ is not bound to the EE version the way the components above are. Both 6.2 and 6.3 build against Jakarta Messaging 3.1 on Java 17. The modules TomEE ships (broker, client, jdbc-store, openwire-legacy, ra) depend only on `jakarta.jms-api`, `jakarta.annotation-api` and `jakarta.resource-api`, and TomEE provides those API jars at its own EE level. 6.3's EE 11 dependencies (Servlet 6.1, EL 6.0, Jetty 12, Spring 7) come only from the web console and the HTTP transport, which TomEE does not ship. tomee-10.x moved to 6.3.2 because CVE-2026-74761 is fixed in no 6.2.x release (TOMEE-4721, apache/tomee#3011). Before a future ActiveMQ minor on either branch, compare `jakarta-jms-api-version` and `javaVersion` in the new `activemq-parent` pom, and the non-test dependencies of those five modules, with the branch's platform.

For a component missing from the table, read the spec version off its release notes or project page (Tomcat publishes it at https://tomcat.apache.org/whichversion.html) and compare it with the spec version the branch's platform lists.

`.github/dependabot.yml` on `main` (it configures both branches) ignores these groups, but its patterns miss things: `io.smallrye:*` did not match `io.smallrye.config`. Treat the ignore list as a first filter; the guardrail is the check. A PR that crosses a line gets closed with a comment naming the line, whatever CI says.

Spec APIs and MicroProfile implementations each get a **spec review** (next section) before any merge. **CXF-aligned libraries** (santuario, woodstox, opensaml) move with CXF: close their PRs, the CXF upgrade brings them.

### Spec review

The review ends in one of two verdicts per PR: **same spec** (merge it like any other PR) or **spec moves** (close it, and name the old and new spec version in the comment).

**Jakarta spec APIs** (`jakarta.*:*`):

1. Read the branch's platform version from `version.jakartaee-api` in the root `pom.xml` (`11.0.x` is EE 11, `10.0.x` is EE 10).
2. Look up the component spec version that platform lists, on `https://jakarta.ee/specifications/platform/<N>/` (the `jakarta-ee-spec-reader` skill does this).
3. Same spec when the new artifact version is a service release of that spec version (`jakarta.faces-api` 4.1.2 → 4.1.3 on EE 11). Spec moves when its major or minor differs from the listed one.

**MicroProfile spec APIs** (`org.eclipse.microprofile*`): the root `pom.xml` pins every spec in a `version.microprofile.<spec>` property. Same spec only for a patch of that exact version (`4.0.1` → `4.0.2`); any other change is a spec move.

**MicroProfile implementations** (`io.smallrye*`, micrometer, opentelemetry, opentracing). The root `pom.xml` pins each implementation in `version.microprofile.impl.<spec>`, next to the spec it implements in `version.microprofile.<spec>`.

1. Read the branch's spec version: `version.microprofile.<spec>` on `origin/<branch>`.
2. Read the spec version the *new* implementation targets, from its parent pom on Maven Central. The SmallRye parents declare it as a property:

   ```sh
   curl -s https://repo.maven.apache.org/maven2/io/smallrye/config/smallrye-config-parent/$V/smallrye-config-parent-$V.pom \
     | grep -iE 'microprofile[^<]*>[0-9]'
   ```

   Other SmallRye projects follow the same layout (`io/smallrye/<project>/smallrye-<project>-parent`). When the parent declares no such property, read the `org.eclipse.microprofile.*` dependency version in the implementation's own pom.
3. Compare major.minor. Equal is same spec; anything else is a spec move. Examples: SmallRye OpenTelemetry 2.7.0 → 2.15.1 moves MP Telemetry 1.1 → 2.1, a spec move on a branch pinned to 1.1. SmallRye Config 3.18.2 → 4.0.0 stays on MP Config 3.1.1, same spec.
4. For a new major of the implementation, also check it still runs on the branch's Java baseline (`maven.compiler.release` in the root `pom.xml`). Read the class file version of one class from the new jar: byte 8 is 61 for Java 17, 65 for Java 21.

   ```sh
   curl -s -o impl.jar <jar url> && unzip -p impl.jar <some .class> | head -c 8 | od -An -tu1
   ```

   A class file version above the baseline counts as a spec move: close it.

A same-spec new major can still break TomEE's integration code, and CI only compiles it. Put it in the gate list as a merge candidate, flagged with the new major, so the user makes the call.

## 1. Collect

```sh
gh pr list -R apache/tomee --author app/dependabot --state open --limit 200 \
  --json number,baseRefName,title,files,statusCheckRollup
```

Also read the unreleased fix versions: `jira_get_project_versions` for `TOMEE`, keep the ones with `released: false` (one per branch, e.g. `11.0.0` for main and `10.3.0` for tomee-10.x).

Done when every open PR has its branch, changed files, and CI state in hand.

## 2. Classify

Sort every PR into exactly one class by what it touches:

- **Build**: Maven plugins, plugin tooling such as `maven-plugin-annotations`, and the `org.apache:apache` parent pom.
- **Misc**: libraries used only by tests, TCK modules, examples, or `utils/` integrations. The test: the artifact appears in no BOM.
- **Shipped**: the artifact appears in a BOM, so it lands in a distribution.

The BOM check, per branch:

```sh
git grep -c "<artifactId>$ARTIFACT" origin/$BRANCH -- 'boms/*/pom.xml'
```

A PR that bumps a version *property* (`version.activemq`, `tomcat.version`) needs the property traced to its artifacts in the root `pom.xml` first.

Then flag, on top of the class:

- anything that breaks the Jakarta EE line guardrail, and the verdict of the spec review for every spec API and MicroProfile implementation PR;
- pre-releases and new majors (`-beta`, `-M`, `-rc`, `X.0.0`), and check their prerequisites. The core Maven plugins' 4.x line needs Maven 4 while the build runs Maven 3, so a 4.x plugin bump fails the first `install`;
- a pom comment that pins the old version on purpose (the rest-client TCK pins old Jetty, for example);
- a failing CI check: read the failed log (`gh run view <id> --log-failed`) and report the actual error.

CI runs `clean install -DskipTests -Pstyle,rat`. Green means it compiles and passes style and license checks; it does not mean tests or TCKs pass. Say so when a bump's risk lives in runtime behaviour.

Done when every PR sits in one class with its flags. **Gate:** show the classes as tables (PR, branch, change, flags).

## 3. Plan Jira

Jira tracks shipped dependencies. Precedent decides which ones: search for earlier issues on each dependency,

```
project = TOMEE AND summary ~ "<name>" ORDER BY created DESC
```

A dependency with past "Dependency upgrade" issues gets one now. Build and misc PRs get none, and neither does a stray precedent on a non-shipped dependency (Hibernate had one by accident; it gets no issue).

For each PR that gets an issue, look for an issue on the same dependency in that branch's unreleased fix version:

- **One exists**: retitle it to the new version and leave its assignee alone.
- **None exists**: create one. Type `Dependency upgrade`, summary `<Name> <version>` (e.g. `Tomcat 11.0.26`, `Apache ActiveMQ 6.2.10`, `MyFaces 4.0.4`), fix version the branch's unreleased version, assignee `jungm`.

Done when every PR has a disposition: close, merge with issue (retitled or new, with the planned summary), or merge without an issue. **Gate:** show the full list with the disposition of every PR.

## 4. Execute

Close first, with a comment giving the reason (the error, the pinned version, the EE line). Closing is the whole response: the user decides on ignore-list changes separately.

For each PR with an issue, in this order:

1. Create or retitle the issue.
2. Rename the PR to `TOMEE-XXXX - <Dependabot title>`.
3. Squash merge with the subject `TOMEE-XXXX - <Dependabot title> (#PR)`:
   `gh pr merge <PR> -R apache/tomee --squash --subject "..."`
4. Transition the issue to Resolved, resolution Fixed. Closed happens at release time.

PRs without an issue get a squash merge with Dependabot's title as the subject.

Merges into a branch make Dependabot rebase the other PRs on it: confirm each PR is still mergeable with a passing check before merging it, and skip and report any that is not.

Done when every PR from the plan is closed or merged and every issue is Resolved. Report the result per PR, with anything skipped and why.
