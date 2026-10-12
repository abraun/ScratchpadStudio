"""QML import lint: every layout/controls/quickshell type a file uses must
have its module imported.

Regression guard: the capture round added ColumnLayout/RowLayout overlays
to BarWidget.qml and StudioWindow.qml without importing QtQuick.Layouts.
The whole widget then failed to compile ("ColumnLayout is not a type",
"Type StudioWindow unavailable") and the captain's bar icon disappeared -
a missing import in one view takes down every surface the plugin hosts.
"""

import re
import sys
from pathlib import Path

PLUGIN_ROOT = Path(__file__).resolve().parent.parent

# type name -> modules that provide it (any one suffices; the shell's
# qs.Ui kit re-exports some control types, e.g. its own Button)
REQUIRED_IMPORTS = {
    "ColumnLayout": ["QtQuick.Layouts"],
    "RowLayout": ["QtQuick.Layouts"],
    "GridLayout": ["QtQuick.Layouts"],
    "StackLayout": ["QtQuick.Layouts"],
    "Button": ["QtQuick.Controls", "qs.Ui"],
    "TextField": ["QtQuick.Controls", "qs.Ui"],
    "TextArea": ["QtQuick.Controls", "qs.Ui"],
    "Slider": ["QtQuick.Controls", "qs.Ui"],
    "ComboBox": ["QtQuick.Controls", "qs.Ui"],
    "CheckBox": ["QtQuick.Controls", "qs.Ui"],
    "ScrollView": ["QtQuick.Controls"],
    "SplitView": ["QtQuick.Controls"],
    "Tumbler": ["QtQuick.Controls"],
    "Dial": ["QtQuick.Controls"],
    "Process": ["Quickshell.Io"],
    "StdioCollector": ["Quickshell.Io"],
    "FileView": ["Quickshell.Io"],
    "Hyprland": ["Quickshell.Hyprland"],
}


def strip_comments_and_strings(source: str) -> str:
    out = []
    i, n = 0, len(source)
    in_str = in_block_comment = in_line_comment = False
    while i < n:
        c = source[i]
        nxt = source[i + 1] if i + 1 < n else ""
        if in_line_comment:
            if c == "\n":
                in_line_comment = False
                out.append(c)
        elif in_block_comment:
            if c == "*" and nxt == "/":
                in_block_comment = False
                i += 1
        elif in_str:
            if c == "\\":
                i += 1
            elif c == '"':
                in_str = False
        else:
            if c == "/" and nxt == "/":
                in_line_comment = True
            elif c == "/" and nxt == "*":
                in_block_comment = True
                i += 1
            elif c == '"':
                in_str = True
            else:
                out.append(c)
        i += 1
    return "".join(out)


def missing_imports(path: Path) -> list[str]:
    source = strip_comments_and_strings(path.read_text())
    imports = set(re.findall(r"^import\s+([\w.]+)", source, re.MULTILINE))
    missing = []
    for type_name, modules in sorted(REQUIRED_IMPORTS.items()):
        if any(module in imports for module in modules):
            continue
        # type used as an instantiation: word boundary, not a property
        # access like ".Button" and not inside another identifier
        if re.search(r"(?<![.\w])" + type_name + r"\s*\{", source):
            missing.append(f"{type_name} without any of: {', '.join(modules)}")
    return missing


def main() -> int:
    failures = []
    for path in sorted(PLUGIN_ROOT.glob("**/*.qml")):
        rel = path.relative_to(PLUGIN_ROOT)
        for problem in missing_imports(path):
            failures.append(f"{rel}: {problem}")
    if failures:
        print("QML import lint failed:")
        for failure in failures:
            print("  " + failure)
        return 1
    print(f"qml import lint ok ({len(list(PLUGIN_ROOT.glob('**/*.qml')))} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
