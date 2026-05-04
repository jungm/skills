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
GITHUB_API = "https://api.github.com/orgs/jakartaee/repos?per_page=100"


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


def words(value: str) -> list[str]:
    return [part for part in re.split(r"[^a-z0-9]+", value.lower()) if part]


def score(text: str, query_words: list[str], version: str | None) -> int:
    haystack = text.lower()
    total = sum(3 for word in query_words if word in haystack)
    if version and version.lower() in haystack:
        total += 5
    return total


def spec_links(query: str, version: str | None) -> list[tuple[int, str, str]]:
    parser = LinkParser()
    parser.feed(fetch_text(SPEC_INDEX))
    query_words = words(query)
    results = []
    for text, href in parser.links:
        url = urllib.parse.urljoin(SPEC_INDEX, href)
        if not url.startswith(SPEC_INDEX):
            continue
        value = f"{text} {url}"
        link_score = score(value, query_words, version)
        if link_score:
            results.append((link_score, text or url, url))
    return sorted(results, reverse=True)[:12]


def github_repos(query: str) -> list[tuple[int, str, str]]:
    repos = json.loads(fetch_text(GITHUB_API))
    query_words = words(query)
    results = []
    for repo in repos:
        value = f"{repo.get('name', '')} {repo.get('description', '')}"
        repo_score = score(value, query_words, None)
        if repo_score:
            results.append((repo_score, repo["name"], repo["html_url"]))
    return sorted(results, reverse=True)[:12]


def tags_for(repo_name: str, version: str | None) -> list[str]:
    tags_url = f"https://api.github.com/repos/jakartaee/{repo_name}/tags?per_page=100"
    try:
        tags = json.loads(fetch_text(tags_url))
    except Exception as exc:
        return [f"Could not fetch tags for jakartaee/{repo_name}: {exc}"]
    names = [tag["name"] for tag in tags]
    if not version:
        return names[:20]
    version_lower = version.lower()
    matching = [name for name in names if version_lower in name.lower()]
    return matching[:20] or names[:20]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("query", help="Specification or technology name, e.g. servlet, restful web services")
    parser.add_argument("--version", help="Requested specification version, e.g. 6.1 or 4.0")
    parser.add_argument("--repo-tags", help="Also list likely tags for a jakartaee repository name")
    args = parser.parse_args()

    try:
        print(f"Specification index: {SPEC_INDEX}")
        print("\nLikely specification pages:")
        for _, text, url in spec_links(args.query, args.version):
            print(f"- {text}: {url}")

        print("\nLikely jakartaee repositories:")
        for _, name, url in github_repos(args.query):
            print(f"- {name}: {url}")

        if args.repo_tags:
            print(f"\nTags for jakartaee/{args.repo_tags}:")
            for tag in tags_for(args.repo_tags, args.version):
                print(f"- {tag}")
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
