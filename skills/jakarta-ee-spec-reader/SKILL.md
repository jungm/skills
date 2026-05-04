---
name: jakarta-ee-spec-reader
description: Locate, read, and cite Jakarta EE specification documentation from authoritative sources. Use when answering questions about Jakarta EE specifications, APIs, TCK requirements, version-specific behavior, spec issue history, or repository source text, especially when the answer should come from https://jakarta.ee/specifications/ or the matching https://github.com/jakartaee/ repository tag instead of memory.
---

# Jakarta EE Spec Reader

## Core Rule

Use current authoritative material. Do not answer specification questions from memory when a published spec page, spec document, API Javadoc, TCK artifact, or tagged `jakartaee` repository can be checked.

Prefer these sources in order:

1. Published pages linked from `https://jakarta.ee/specifications/`.
2. Version-specific PDF/HTML spec documents, API Javadocs, schemas, and TCK links reached from those pages.
3. Tagged source repositories under `https://github.com/jakartaee/` when the published page links a repository or when source history, exact AsciiDoc text, or issue context is needed.

## Workflow

1. Identify the exact specification and version needed.
   - If the user names a Jakarta EE platform release, map it to the component specification version before reading component text.
   - If the user asks about latest/current behavior, browse `https://jakarta.ee/specifications/` first because versions can change.
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

## Helper Script

Use `scripts/jakarta_spec_sources.py` to orient quickly before browsing or cloning:

```bash
python3 /path/to/skill/scripts/jakarta_spec_sources.py "restful web services" --version 4.0
python3 /path/to/skill/scripts/jakarta_spec_sources.py "servlet"
```

The script searches `jakarta.ee/specifications`, prints likely specification pages, and can list matching `jakartaee` repositories and tags when network access is available. Treat the output as orientation, not proof; verify final claims from the linked source.

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

- Treat final specification documents and API Javadocs as normative over examples, guides, blogs, issue comments, and draft source files.
- Use TCK sources to understand tested behavior, but do not present tests as the specification unless the spec or assertions document supports it.
- For generated specs, repository AsciiDoc may differ from the published final artifact; prefer the published artifact for final wording.
- When quoting, keep excerpts short and explain the rule in your own words.
- If a question spans multiple specs, read each relevant spec page and call out cross-spec boundaries instead of merging requirements.

## Reference

Read `references/source-selection.md` when the task involves choosing between platform specs, component specs, API docs, TCKs, and repository source.
