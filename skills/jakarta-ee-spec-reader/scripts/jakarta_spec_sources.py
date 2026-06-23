#!/usr/bin/env python3
"""Orient on Jakarta EE specification pages and matching GitHub repositories."""

from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.parse
import urllib.request
from html.parser import HTMLParser


SPEC_INDEX = "https://jakarta.ee/specifications/"
GITHUB_API = "https://api.github.com/orgs/jakartaee/repos"


class LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[tuple[str, str]] = []
        self._href: str | None = None
        self._text: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "a":
            return
        attrs_dict = dict(attrs)
        self._href = attrs_dict.get("href")
        self._text = []

    def handle_data(self, data: str) -> None:
        if self._href is not None:
            self._text.append(data)

    def handle_endtag(self, tag: str) -> None:
        if tag == "a" and self._href:
            text = " ".join(" ".join(self._text).split())
            self.links.append((text, self._href))
            self._href = None
            self._text = []


def fetch_text(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "codex-jakarta-ee-spec-reader"})
    with urllib.request.urlopen(req, timeout=20) as response:
        return response.read().decode("utf-8", errors="replace")


def fetch_json_pages(url: str) -> list[dict[str, object]]:
    items: list[dict[str, object]] = []
    page = 1
    while True:
        separator = "&" if "?" in url else "?"
        data = json.loads(fetch_text(f"{url}{separator}per_page=100&page={page}"))
        if not data:
            return items
        items.extend(data)
        if len(data) < 100:
            return items
        page += 1


def words(value: str) -> list[str]:
    return [part for part in re.split(r"[^a-z0-9]+", value.lower()) if part]


def score(text: str, query_words: list[str], version: str | None) -> int:
    haystack = text.lower()
    haystack_words = set(words(text))
    total = sum(5 for word in query_words if word in haystack_words)
    total += sum(1 for word in query_words if word not in haystack_words and word in haystack)
    if version and version.lower() in haystack:
        total += 5
    if "under development" in haystack:
        total -= 2
    if "view more" in haystack:
        total -= 3
    return total


def spec_links(query: str, version: str | None) -> list[tuple[int, str, str]]:
    parser = LinkParser()
    parser.feed(fetch_text(SPEC_INDEX))
    query_words = words(query)
    results = []
    for text, href in parser.links:
        if text.strip().lower() == "view more":
            continue
        url = urllib.parse.urljoin(SPEC_INDEX, href)
        if not url.startswith(SPEC_INDEX):
            continue
        value = f"{text} {url}"
        link_score = score(value, query_words, version)
        if link_score > 0:
            results.append((link_score, text or url, url))
    return sorted(results, reverse=True)[:12]


def github_repos(query: str) -> list[tuple[int, str, str]]:
    repos = fetch_json_pages(GITHUB_API)
    query_words = words(query)
    results = []
    for repo in repos:
        name = str(repo.get("name", ""))
        value = f"{name} {repo.get('description', '')}"
        repo_score = score(value, query_words, None)
        if query.lower().replace(" ", "-") == name.lower():
            repo_score += 8
        if repo_score > 0:
            results.append((repo_score, name, str(repo["html_url"])))
    return sorted(results, reverse=True)[:12]


def tags_for(repo_name: str, version: str | None) -> list[str]:
    tags_url = f"https://api.github.com/repos/jakartaee/{repo_name}/tags"
    try:
        tags = fetch_json_pages(tags_url)
    except Exception as exc:
        return [f"Could not fetch tags for jakartaee/{repo_name}: {exc}"]
    names = [str(tag["name"]) for tag in tags]
    if not version:
        return names[:20]
    version_lower = version.lower()
    matching = [name for name in names if version_lower in name.lower()]
    return matching[:20] or names[:20]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", help="Specification or technology name, e.g. servlet, restful web services")
    parser.add_argument("--version", help="Requested specification version, e.g. 6.1 or 4.0")
    parser.add_argument("--repo-tags", metavar="REPO", help="Also list likely tags for a jakartaee repository name")
    parser.add_argument("--tags", action="store_true", help="Also list likely tags for the top repository match")
    args = parser.parse_args()

    try:
        print(f"Specification index: {SPEC_INDEX}")
        print("\nLikely specification pages:")
        specs = spec_links(args.query, args.version)
        if not specs:
            print("- No likely specification pages found")
        for _, text, url in specs:
            print(f"- {text}: {url}")

        print("\nLikely jakartaee repositories:")
        repos = github_repos(args.query)
        if not repos:
            print("- No likely repositories found")
        for _, name, url in repos:
            print(f"- {name}: {url}")

        tag_repo = args.repo_tags or (repos[0][1] if args.tags and repos else None)
        if tag_repo:
            print(f"\nTags for jakartaee/{tag_repo}:")
            for tag in tags_for(tag_repo, args.version):
                print(f"- {tag}")
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
