---
name: jakarta-ee-spec-reader
description: Locate, read, and cite Jakarta EE specification documentation from authoritative sources. Use when answering questions about Jakarta EE specifications, APIs, TCK requirements, version-specific behavior, spec issue history, or repository source text, especially when the answer should come from https://jakarta.ee/specifications/ or the matching https://github.com/jakartaee/ repository tag instead of memory.
---

# Jakarta EE Spec Reader

## Core Rule

Use current authoritative material. Do not answer specification questions from memory when a published spec page, spec document, API Javadoc, TCK artifact, or tagged `jakartaee` repository can be checked.

Prefer sources in this order:

1. Published pages linked from `https://jakarta.ee/specifications/`.
2. Version-specific PDF/HTML spec documents, API Javadocs, schemas, and TCK links reached from those pages.
3. Tagged source repositories under `https://github.com/jakartaee/` when the published page links a repository or when source history, exact AsciiDoc text, or issue context is needed.

## Workflow

1. Identify the exact specification and version needed.
   - If the user names a Jakarta EE platform or profile release, use its specification page to map platform/profile membership to component specification versions before reading component text.
   - If the user asks about latest/current behavior, browse `https://jakarta.ee/specifications/` first because versions can change. Prefer the latest final release unless the user asks for a draft or unreleased version.
   - If the version is ambiguous and the answer may differ by version, say which version you used.

2. Start from `https://jakarta.ee/specifications/`.
   - Open the relevant specification family page.
   - Select the requested version row.
   - Use that page's links for spec document, API, TCK, compatible implementations, Maven coordinates, and source repository.

3. Use repositories only with a matching tag.
   - Do not rely on `main`, `master`, or a default branch for normative answers unless the user explicitly asks for unreleased work.
   - List tags and choose the tag matching the published specification version, for example `4.0.0`, `jakarta-restful-ws-4.0.0`, or another repo-specific naming pattern.
   - If no exact tag exists, compare the published page, releases, and nearby tags; state the uncertainty before using repository text.

4. Cite the source precisely.
   - Include links to the spec page and document or tagged repository file used.
   - Mention the specification name and version in the answer.
   - For GitHub source, include the tag/commit. Prefer immutable tag URLs over branch URLs.

## Source Selection

- Use platform/profile specifications for membership, required component versions, release-wide compatibility, deprecations, removals, and Core/Web/Profile boundaries.
- Use component specifications for API behavior, provider/container requirements, annotations, lifecycle, deployment, configuration, protocols, serialization, persistence, validation, REST, servlet, messaging, and security rules.
- Use API Javadocs for signatures, annotation targets, default values, exception contracts, and package/class-level requirements.
- Use TCK material to understand tested behavior, assertion IDs, or compatibility failures, but do not present one test as the specification unless the spec or assertions document supports it.
- Treat final specification documents and API Javadocs as normative over examples, guides, blogs, issue comments, draft source files, and repository branches.
- If Javadoc and prose appear to conflict, report both and prefer the final published artifact unless a specification maintenance issue clarifies it.

## Helper Script

Use `scripts/jakarta_spec_sources.py` to orient quickly before browsing or cloning:

```bash
python3 /path/to/skill/scripts/jakarta_spec_sources.py "restful web services" --version 4.0
python3 /path/to/skill/scripts/jakarta_spec_sources.py "servlet" --version 6.1 --tags
python3 /path/to/skill/scripts/jakarta_spec_sources.py "persistence" --repo-tags persistence
```

The script searches `jakarta.ee/specifications`, prints likely specification pages and `jakartaee` repositories, and can list tags when network access is available. Treat the output as orientation, not proof; verify final claims from the linked source.

## Repository Checks

When local source inspection is useful:

```bash
git ls-remote --tags https://github.com/jakartaee/<repo>.git
git clone --filter=blob:none --no-checkout https://github.com/jakartaee/<repo>.git <tmpdir>
git -C <tmpdir> checkout <tag>
rg "<term>" <tmpdir>
```

Use a temporary directory for clones unless the user wants a persistent checkout. Keep clones read-only for research tasks.

## Reading Guidance

- For generated specs, repository AsciiDoc may differ from the published final artifact; prefer the published artifact for final wording.
- Platform release numbers do not always equal component specification versions.
- Historical specs may use old Java EE package names; verify whether the user asked about Jakarta namespace behavior.
- When quoting, keep excerpts short and explain the rule in your own words.
- If a question spans multiple specs, read each relevant spec page and call out cross-spec boundaries instead of merging requirements.
