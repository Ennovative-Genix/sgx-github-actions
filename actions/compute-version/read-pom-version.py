"""Print the project version declared by ./pom.xml, or nothing if there is none.

Line-based matching gets this wrong in two common cases:

  * A <parent> block declares a <version> *before* the project's own, so taking
    the first match returns the parent's version. Every Spring Boot pom hits this.
  * Dependencies declare versions too, so taking the last match is worse.

Maven's actual rule is that the project's own <version> wins, and the parent's is
inherited only when the project omits it.
"""

import sys
import xml.etree.ElementTree as ElementTree


def local_name(tag: str) -> str:
    """Strip the XML namespace, which poms may or may not declare."""
    return tag.rsplit("}", 1)[-1]


def direct_child(parent, name):
    for child in parent:
        if local_name(child.tag) == name:
            return child
    return None


def main() -> int:
    try:
        root = ElementTree.parse("pom.xml").getroot()
    except (OSError, ElementTree.ParseError) as error:
        print(f"could not read pom.xml: {error}", file=sys.stderr)
        return 1

    version = direct_child(root, "version")

    if version is None:
        parent = direct_child(root, "parent")
        if parent is not None:
            version = direct_child(parent, "version")

    if version is not None and version.text:
        print(version.text.strip())

    return 0


if __name__ == "__main__":
    sys.exit(main())
