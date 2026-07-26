"""Fail if any reusable-workflow call chain would exceed GitHub's nesting limit.

GitHub connects a maximum of four levels of workflows, and the consuming
repository's own workflow file counts as the first. So a chain of three files in
this repository is the most that can be reached from a consumer's workflow.

The entry points sit one level above the pipelines, which puts

    consumer -> deploy.yml -> pipeline-ec2.yml -> build-docker-s3.yml

exactly at the limit. Adding another layer anywhere below an entry point breaks
every consumer at runtime, with an error that points at their file rather than
this one. This check turns that into a failed pull request instead.
"""

import pathlib
import sys

import yaml

MAX_LEVELS = 4
WORKFLOWS = pathlib.Path(".github/workflows")
LOCAL_PREFIX = "./.github/workflows/"


def called_workflows(path: pathlib.Path) -> list[str]:
    document = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    targets = []

    for job in (document.get("jobs") or {}).values():
        uses = job.get("uses") or ""
        if uses.startswith(LOCAL_PREFIX):
            targets.append(uses.rsplit("/", 1)[-1])

    return targets


def deepest_chain(name, graph, visiting=()):
    """Return the longest chain of workflow files starting at `name`."""
    if name in visiting:
        # A cycle would hang the runner rather than fail cleanly.
        return [*visiting, f"{name} (CYCLE)"]

    longest = [name]

    for target in graph.get(name, []):
        chain = deepest_chain(target, graph, (*visiting, name))
        if len(chain) + 1 > len(longest):
            longest = [name, *chain]

    return longest


def main() -> int:
    graph = {path.name: called_workflows(path) for path in sorted(WORKFLOWS.glob("*.yml"))}

    # Anything nothing else calls is reachable directly by a consumer.
    called_by_someone = {target for targets in graph.values() for target in targets}
    entry_points = sorted(name for name in graph if name not in called_by_someone)

    failures = 0

    for name in entry_points:
        chain = deepest_chain(name, graph)
        levels = len(chain) + 1  # +1 for the consumer's own workflow file

        rendered = "consumer -> " + " -> ".join(chain)

        if any("(CYCLE)" in step for step in chain):
            print(f"::error file={WORKFLOWS / name}::Cyclic workflow call: {rendered}")
            failures += 1
        elif levels > MAX_LEVELS:
            print(
                f"::error file={WORKFLOWS / name}::Chain is {levels} levels deep, "
                f"over GitHub's limit of {MAX_LEVELS}: {rendered}"
            )
            failures += 1
        else:
            marker = "at limit" if levels == MAX_LEVELS else "ok"
            print(f"  {levels}  {marker:9} {rendered}")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
