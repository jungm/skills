# Source Selection

Use this reference when a Jakarta EE question has multiple plausible authorities.

## Published Specification Pages

Start at `https://jakarta.ee/specifications/`. The family and version pages are the best index because they link the final specification document, API docs, TCK, Maven coordinates, compatible implementations, and source repositories for a release.

Use the platform specification for:

- Platform membership and required component versions.
- Profiles such as Core Profile, Web Profile, and Platform.
- Release-wide compatibility, deprecation, or removal questions.

Use component specifications for:

- API behavior.
- Provider/container requirements.
- Annotations, lifecycle, deployment, configuration, protocol, serialization, persistence, validation, REST, servlet, messaging, or security rules.

## API Javadocs

Use API Javadocs for signatures, annotation targets, default values, exception contracts, and package/class-level requirements. If Javadoc and prose appear to conflict, report both and prefer the final published artifact unless a specification maintenance issue clarifies it.

## TCK Material

Use TCK documentation and tests for:

- Confirming how a rule is tested.
- Finding assertion IDs or test names.
- Investigating compatibility failures.

Do not infer broad normative requirements from one TCK test when the spec text is narrower or ambiguous.

## GitHub Repositories

Use `https://github.com/jakartaee/` repositories for:

- Tagged AsciiDoc source matching a published release.
- Issue and PR history.
- Build metadata, schemas, examples, and TCK sources not exposed directly from the published page.

Always verify the tag:

1. Read the published spec version.
2. List repository tags.
3. Prefer an exact semantic version tag or repo-specific release tag.
4. Use a commit only when no suitable tag exists, and explain why.

## Common Pitfalls

- The latest branch may describe the next release, not the released version.
- Platform release numbers do not always equal component specification versions.
- Old Java EE package names may appear in historical specs; verify whether the user asked about Jakarta namespace behavior.
- Generated HTML/PDF may contain final wording that is absent or reorganized in source files.
