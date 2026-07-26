"""Fail if README.md's entry-point reference has drifted from the real contract.

The entry points are the documented surface of this repository. An input that
exists but is not in the table is invisible; an input in the table that no longer
exists sends people to write `with:` keys that GitHub rejects. Both are the kind
of rot that a reference table accumulates silently, so it is checked rather than
trusted.

Only inputs are compared. The secrets and outputs tables live below the
`**Secrets**` heading and are matched by name elsewhere.
"""

import pathlib
import re
import sys

import yaml

README = pathlib.Path("README.md")
WORKFLOWS = pathlib.Path(".github/workflows")
ENTRY_POINTS = ["deploy.yml", "publish.yml"]

# Table rows look like: | `input_name` | string | `default` | Description |
ROW = re.compile(r"^\|\s*`([a-z0-9_]+)`\s*\|", re.MULTILINE)


def declared_inputs(name: str) -> set[str]:
    document = yaml.safe_load((WORKFLOWS / name).read_text(encoding="utf-8"))
    triggers = document.get("on") or document.get(True) or {}
    return set((triggers["workflow_call"].get("inputs") or {}))


def documented_inputs(readme: str, name: str) -> set[str] | None:
    section = re.search(
        r"<summary><b><code>" + re.escape(name) + r"</code>.*?</details>",
        readme,
        re.DOTALL,
    )
    if section is None:
        return None

    # Everything from the secrets heading onward describes something else.
    body = re.split(r"\*\*Secrets\*\*", section.group(0))[0]
    return set(ROW.findall(body))


def main() -> int:
    readme = README.read_text(encoding="utf-8")
    failures = 0

    for name in ENTRY_POINTS:
        actual = declared_inputs(name)
        documented = documented_inputs(readme, name)

        if documented is None:
            print(f"::error file=README.md::No input reference section for '{name}'.")
            failures += 1
            continue

        for missing in sorted(actual - documented):
            print(
                f"::error file=README.md::'{name}' declares input '{missing}', "
                f"which is not in the README reference table."
            )
            failures += 1

        for stale in sorted(documented - actual):
            print(
                f"::error file=README.md::README documents input '{stale}' for "
                f"'{name}', which the workflow does not declare."
            )
            failures += 1

        if actual == documented:
            print(f"  {name}: {len(actual)} inputs, all documented")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
