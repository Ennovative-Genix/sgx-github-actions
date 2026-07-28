"""Print the version declared in ./pyproject.toml, or nothing.

Nothing is a valid answer: a project using a dynamic version has no string to
read here, and the caller treats an empty result the same as a missing manifest.
"""

import pathlib
import re
import sys

path = pathlib.Path("pyproject.toml")
if not path.exists():
    sys.exit(0)

text = path.read_text(encoding="utf-8")
version = ""

try:
    # tomllib landed in 3.11. Parsing beats a line match because it cannot
    # confuse the project version with a dependency pin of the same shape.
    import tomllib

    data = tomllib.loads(text)
    version = (
        data.get("project", {}).get("version")
        or data.get("tool", {}).get("poetry", {}).get("version")
        or ""
    )
except Exception:
    # Older interpreter, or a file tomllib refuses. The first top-level
    # `version = "..."` is the package version in every layout we publish.
    match = re.search(r'(?m)^version\s*=\s*["\']([^"\']+)["\']', text)
    version = match.group(1) if match else ""

sys.stdout.write(version)
