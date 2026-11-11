#!/usr/bin/env python3
"""Generates the Python API reference pages in docs/python-api/.

Reads the `pixzig` Python package's source with `ast` (nothing is imported,
so no engine library is needed) and writes one Markdown page per module for
zkdocs, from the Google-style docstrings:

    Summary line.

    Longer description. A block indented four spaces past the text around
    it, after a blank line, becomes a code block.

    Args:
        name: What it is. Continuation lines are
            indented further.

    Returns:
        What comes back.

    Raises:
        ValueError: When.

`Attributes:`, `Yields:`, `Example:`/`Examples:` and `Note:` sections work
the same way. A backticked name such as `App.load_sprite`, `Sprite` or
`pixzig.easing` that names something documented here becomes a link to it.

The pages list in docs/zkdocs.conf names these files, so adding a module
here means adding it there too. Usage:

    tools/gen_py_docs.py            # write docs/python-api/*.md
    tools/gen_py_docs.py --check    # exit 1 if the pages are out of date

`zig build docs` runs this first, so the site never shows stale pages.
"""

import argparse
import ast
import inspect
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
PKG = REPO / "python" / "pixzig"
OUT_DIR = REPO / "docs" / "python-api"
# The pages' slug prefix in zkdocs: `page:python-api/<module>`.
SLUG_DIR = "python-api"

# (module file stem, page title), in the order the docs list them. "__init__"
# is the package overview.
MODULES = [
    ("__init__", "Overview"),
    ("app", "App"),
    ("input", "Input"),
    ("action", "Action Maps"),
    ("sprite", "Sprites"),
    ("anim", "Animation"),
    ("text", "Text"),
    ("shapes", "Shapes"),
    ("camera", "Camera"),
    ("window", "Window"),
    ("render_target", "Render Targets"),
    ("audio", "Audio"),
    ("tilemap", "Tile Maps"),
    ("manifest", "Asset Manifests"),
    ("event", "Events"),
    ("constants", "Constants"),
    ("sequence", "pixzig.sequence"),
    ("states", "pixzig.states"),
    ("collision", "pixzig.collision"),
    ("color", "pixzig.color"),
    ("easing", "pixzig.easing"),
    ("save", "pixzig.save"),
    ("paths", "pixzig.paths"),
]

SECTION_NAMES = {
    "Args": "args",
    "Arguments": "args",
    "Attributes": "attributes",
    "Returns": "returns",
    "Yields": "yields",
    "Raises": "raises",
    "Example": "example",
    "Examples": "example",
    "Note": "note",
    "Notes": "note",
}

# The first word of a code block that reads as a shell command rather than
# Python, for picking the fence's language.
SHELL_WORDS = {"python", "python3", "pip", "cd", "zig", "just", "uv"}


def slugify(text: str) -> str:
    """zkdocs's heading slug: lowercase alphanumerics, other runs as one hyphen."""
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


# ---------------------------------------------------------------------------
# Model


@dataclass
class Member:
    """A documented function, method or property."""

    name: str
    kind: str  # "function", "method", "property", "classmethod"
    signature: str
    doc: str
    params: dict  # name -> (annotation, default), in order


@dataclass
class Cls:
    name: str
    doc: str
    bases: list
    init_params: dict
    init_signature: str
    members: list = field(default_factory=list)
    # Class-level NAME = value assignments, for enum-like classes.
    constants: list = field(default_factory=list)


@dataclass
class Module:
    stem: str
    title: str
    doc: str
    classes: list = field(default_factory=list)
    functions: list = field(default_factory=list)

    @property
    def slug(self) -> str:
        return f"{SLUG_DIR}/{'index' if self.stem == '__init__' else self.stem}"

    @property
    def dotted(self) -> str:
        return "pixzig" if self.stem == "__init__" else f"pixzig.{self.stem}"


def _unparse(node) -> str:
    return ast.unparse(node) if node is not None else ""


def _params(fn: ast.FunctionDef, skip_first: bool):
    """The parameters as name -> (annotation, default), and a signature string."""
    args = fn.args
    positional = args.posonlyargs + args.args
    defaults = [None] * (len(positional) - len(args.defaults)) + list(args.defaults)
    params = {}
    parts = []
    for i, (a, d) in enumerate(zip(positional, defaults)):
        if skip_first and i == 0:
            continue
        params[a.arg] = (_unparse(a.annotation), _unparse(d) if d is not None else None)
        parts.append(_param_str(a, d))
    if args.vararg:
        params["*" + args.vararg.arg] = (_unparse(args.vararg.annotation), None)
        parts.append("*" + _param_str(args.vararg, None))
    elif args.kwonlyargs:
        parts.append("*")
    for a, d in zip(args.kwonlyargs, args.kw_defaults):
        params[a.arg] = (_unparse(a.annotation), _unparse(d) if d is not None else None)
        parts.append(_param_str(a, d))
    if args.kwarg:
        params["**" + args.kwarg.arg] = (_unparse(args.kwarg.annotation), None)
        parts.append("**" + _param_str(args.kwarg, None))
    ret = f" -> {_unparse(fn.returns)}" if fn.returns is not None else ""
    return params, f"({', '.join(parts)}){ret}"


def _param_str(a: ast.arg, default) -> str:
    s = a.arg
    if a.annotation is not None:
        s += f": {_unparse(a.annotation)}"
        if default is not None:
            s += f" = {_unparse(default)}"
    elif default is not None:
        s += f"={_unparse(default)}"
    return s


def _decorators(fn) -> set:
    return {_unparse(d) for d in fn.decorator_list}


def load_module(stem: str, title: str) -> Module:
    tree = ast.parse((PKG / f"{stem}.py").read_text())
    mod = Module(stem, title, ast.get_docstring(tree) or "")
    if stem == "__init__":
        # The package re-exports `Error` from the private `_native`, so the
        # overview documents it.
        native = ast.parse((PKG / "_native.py").read_text())
        for node in native.body:
            if isinstance(node, ast.ClassDef) and node.name == "Error":
                mod.classes.append(load_class(node))
    for node in tree.body:
        if isinstance(node, ast.ClassDef) and not node.name.startswith("_"):
            mod.classes.append(load_class(node))
        elif isinstance(node, ast.FunctionDef) and not node.name.startswith("_"):
            params, sig = _params(node, skip_first=False)
            mod.functions.append(Member(node.name, "function", sig, ast.get_docstring(node) or "", params))
    return mod


def load_class(node: ast.ClassDef) -> Cls:
    init_params, init_sig = {}, "()"
    cls = Cls(node.name, ast.get_docstring(node) or "", [_unparse(b) for b in node.bases], {}, "")
    seen = set()
    for item in node.body:
        if isinstance(item, ast.FunctionDef):
            if item.name == "__init__":
                init_params, init_sig = _params(item, skip_first=True)
                continue
            if item.name.startswith("_") or item.name in seen:
                continue
            seen.add(item.name)
            decos = _decorators(item)
            if "property" in decos:
                kind = "property"
                ret = f": {_unparse(item.returns)}" if item.returns is not None else ""
                params, sig = {}, ret
            elif "classmethod" in decos or "staticmethod" in decos:
                kind = "classmethod"
                params, sig = _params(item, skip_first="classmethod" in decos)
            else:
                kind = "method"
                params, sig = _params(item, skip_first=True)
            cls.members.append(Member(item.name, kind, sig, ast.get_docstring(item) or "", params))
        elif isinstance(item, ast.Assign) and len(item.targets) == 1 and isinstance(item.targets[0], ast.Name):
            name = item.targets[0].id
            if not name.startswith("_"):
                cls.constants.append((name, _unparse(item.value)))
    cls.init_params, cls.init_signature = init_params, init_sig
    return cls


# ---------------------------------------------------------------------------
# Docstring parsing


@dataclass
class Doc:
    description: str
    sections: dict  # kind -> list of (name, text) for entry sections, or str


def parse_doc(text: str) -> Doc:
    """Splits a cleaned docstring into its description and Google sections."""
    lines = inspect.cleandoc(text).splitlines() if text else []
    desc, sections = [], {}
    current, body = None, []

    def flush():
        if current is not None:
            sections[current] = _parse_section(current, body)

    for line in lines:
        header = line.rstrip()
        if header.endswith(":") and header[:-1] in SECTION_NAMES and not line.startswith(" "):
            flush()
            current, body = SECTION_NAMES[header[:-1]], []
        elif current is None:
            desc.append(line)
        else:
            body.append(line)
    flush()
    return Doc("\n".join(desc).strip("\n"), sections)


def _dedent(lines, by=4):
    return [ln[by:] if ln.startswith(" " * by) else ln.lstrip() for ln in lines]


def _parse_section(kind: str, body):
    if kind in ("args", "attributes", "raises"):
        entries = []
        for line in body:
            if not line.strip():
                if entries:
                    entries[-1][1] += "\n\n"
                continue
            indent = len(line) - len(line.lstrip())
            m = re.match(r"^\s*(\*{0,2}[\w.]+)(?:\s*\([^)]*\))?:\s*(.*)$", line)
            if indent <= 4 and m:
                entries.append([m.group(1), m.group(2)])
            elif entries:
                sep = "" if entries[-1][1].endswith("\n\n") else " "
                entries[-1][1] += sep + line.strip()
        return [(n, t.strip()) for n, t in entries]
    # Free text: Returns, Yields, Example, Note.
    return "\n".join(_dedent(body)).strip("\n")


# ---------------------------------------------------------------------------
# Cross references


class Linker:
    """Turns backticked names into links to where they're documented."""

    def __init__(self, modules):
        self.targets = {}  # name -> page link
        for mod in modules:
            self.targets.setdefault(mod.dotted, f"page:{mod.slug}")
            for cls in mod.classes:
                anchor = f"page:{mod.slug}#h2-{slugify(cls.name)}"
                self.targets.setdefault(cls.name, anchor)
                self.targets.setdefault(f"pixzig.{cls.name}", anchor)
                self.targets.setdefault(f"{mod.dotted}.{cls.name}", anchor)
                for m in cls.members:
                    q = f"{cls.name}.{m.name}"
                    self.targets.setdefault(q, f"page:{mod.slug}#h3-{slugify(q)}")
            for fn in mod.functions:
                link = f"page:{mod.slug}#h2-{slugify(fn.name)}"
                self.targets.setdefault(f"{mod.dotted}.{fn.name}", link)
                self.targets.setdefault(f"{mod.stem}.{fn.name}", link)

    def link(self, text: str, context_cls: Cls = None) -> str:
        """Links each `name` (outside fenced code) that's documented here."""
        out, in_fence = [], False
        for line in text.split("\n"):
            if line.lstrip().startswith("```"):
                in_fence = not in_fence
                out.append(line)
                continue
            out.append(line if in_fence else self._link_line(line, context_cls))
        return "\n".join(out)

    def _link_line(self, line: str, context_cls) -> str:
        def repl(m):
            name = m.group(1)
            target = self._resolve(name, context_cls)
            return f"[`{name}`]({target})" if target else m.group(0)

        # Skip backticks already inside link text, e.g. [`x`](...).
        return re.sub(r"(?<!\[)`([A-Za-z_][\w.]*)(?:\(\))?`(?!\])", repl, line)

    def _resolve(self, name: str, context_cls):
        bare = name[len("pixzig."):] if name.startswith("pixzig.") and name not in self.targets else name
        for candidate in (name, bare):
            if candidate in self.targets:
                return self.targets[candidate]
        if context_cls is not None and f"{context_cls.name}.{name}" in self.targets:
            return self.targets[f"{context_cls.name}.{name}"]
        # `app.create_camera` / `app.text`: an App instance's members.
        if name.startswith("app.") and f"App.{name[4:]}" in self.targets:
            return self.targets[f"App.{name[4:]}"]
        return None


# ---------------------------------------------------------------------------
# Rendering


def prose(text: str) -> str:
    """Docstring prose as Markdown: indented blocks after a blank line become
    fenced code, and the rest passes through."""
    lines = text.split("\n")
    out, i = [], 0
    while i < len(lines):
        line = lines[i]
        prev_blank = i == 0 or not lines[i - 1].strip()
        if prev_blank and line.startswith("    ") and line.strip():
            block = []
            while i < len(lines) and (lines[i].startswith("    ") or not lines[i].strip()):
                block.append(lines[i])
                i += 1
            while block and not block[-1].strip():
                block.pop()
            code = "\n".join(_dedent_common(block))
            first = code.split(None, 1)[0] if code.strip() else ""
            lang = "sh" if first in SHELL_WORDS else ("json" if code.lstrip().startswith("{") else "python")
            out.append(f"```{lang}\n{code}\n```")
            out.append("")
            continue
        out.append(line)
        i += 1
    return "\n".join(out).strip("\n")


def _dedent_common(block):
    indents = [len(ln) - len(ln.lstrip()) for ln in block if ln.strip()]
    cut = min(indents) if indents else 0
    return [ln[cut:] for ln in block]


def cell(text: str) -> str:
    """Text made safe for one Markdown table cell."""
    return text.replace("\n\n", " ").replace("\n", " ").replace("|", "&#124;").strip()


def render_doc(doc: Doc, linker: Linker, params=None, context_cls=None, constants=None) -> list:
    """The description and sections of one docstring, as Markdown lines."""
    out = []
    if doc.description:
        out += [linker.link(prose(doc.description), context_cls), ""]

    args = doc.sections.get("args")
    if args:
        params = params or {}
        show_defaults = any(params.get(n, ("", None))[1] is not None for n, _ in args)
        show_types = any(params.get(n, ("", None))[0] for n, _ in args)
        head = ["Argument"] + (["Type"] if show_types else []) + (["Default"] if show_defaults else []) + ["Description"]
        out += ["| " + " | ".join(head) + " |", "|" + "---|" * len(head)]
        for name, text in args:
            ann, default = params.get(name.lstrip("*"), params.get(name, ("", None)))
            row = [f"`{name}`"]
            if show_types:
                row.append(f"`{ann}`" if ann else "")
            if show_defaults:
                row.append(f"`{default}`" if default is not None else "")
            row.append(cell(linker.link(text, context_cls)))
            out.append("| " + " | ".join(row) + " |")
        out.append("")

    attrs = doc.sections.get("attributes")
    if attrs:
        values = dict(constants or [])
        if values:
            out += ["| Name | Value | Description |", "|---|---|---|"]
            for name, text in attrs:
                val = f"`{values[name]}`" if name in values else ""
                out.append(f"| `{name}` | {val} | {cell(linker.link(text, context_cls))} |")
        else:
            out += ["| Attribute | Description |", "|---|---|"]
            for name, text in attrs:
                out.append(f"| `{name}` | {cell(linker.link(text, context_cls))} |")
        out.append("")

    for kind, label in (("returns", "Returns"), ("yields", "Yields")):
        text = doc.sections.get(kind)
        if text:
            out += [f"**{label}:** {linker.link(prose(text), context_cls)}", ""]

    raises = doc.sections.get("raises")
    if raises:
        out.append("**Raises:**")
        out.append("")
        for name, text in raises:
            out.append(f"- `{name}`: {cell(linker.link(text, context_cls))}")
        out.append("")

    note = doc.sections.get("note")
    if note:
        out.append("!!! note")
        out += ["    " + ln if ln.strip() else "" for ln in linker.link(prose(note), context_cls).split("\n")]
        out.append("")

    example = doc.sections.get("example")
    if example:
        out += ["**Example:**", "", linker.link(prose(example), context_cls), ""]
    return out


def render_class(cls: Cls, linker: Linker) -> list:
    out = [f"## `{cls.name}`", ""]
    doc = parse_doc(cls.doc)
    is_tuple = any(b.startswith("namedtuple") or b == "NamedTuple" for b in cls.bases)
    if "args" in doc.sections:
        out += ["```python", _fit(cls.name, cls.init_signature), "```", ""]
    elif cls.bases and not is_tuple and cls.bases != ["Exception"]:
        bases = ", ".join(linker.link(f"`{b}`") for b in cls.bases)
        out += [f"Subclass of {bases}.", ""]
    elif cls.bases == ["Exception"]:
        out += ["Subclass of `Exception`.", ""]
    out += render_doc(doc, linker, cls.init_params, cls, cls.constants)

    # An enum-like class whose docstring doesn't list its members.
    if cls.constants and "attributes" not in doc.sections:
        names = [n for n, _ in cls.constants]
        out += ["Members:", "", "```python", _wrap(names), "```", ""]

    for m in cls.members:
        out += render_member(m, linker, cls)
    return out


def _wrap(names, width=76) -> str:
    lines, cur = [], ""
    for n in names:
        piece = (", " if cur else "") + n
        if len(cur) + len(piece) > width:
            lines.append(cur + ",")
            cur = n
        else:
            cur += piece
    if cur:
        lines.append(cur)
    return "\n".join(lines)


def _fit(name: str, signature: str, width: int = 88) -> str:
    """`name(signature)`, one parameter per line when it's too long for one."""
    one = f"{name}{signature}"
    if len(one) <= width:
        return one
    params, _, ret = signature[1:].rpartition(")")
    parts, depth, cur = [], 0, ""
    for ch in params:
        if ch == "," and depth == 0:
            parts.append(cur.strip())
            cur = ""
            continue
        depth += ch in "([{"
        depth -= ch in ")]}"
        cur += ch
    if cur.strip():
        parts.append(cur.strip())
    body = "".join(f"    {p},\n" for p in parts)
    return f"{name}(\n{body}){ret}"


def render_member(m: Member, linker: Linker, cls: Cls = None) -> list:
    qual = f"{cls.name}.{m.name}" if cls else m.name
    # Backticks keep zmd from reading underscores as emphasis, which would
    # also change the heading's anchor.
    out = [f"### `{qual}`" if cls else f"## `{qual}`", ""]
    if m.kind == "property":
        out += ["```python", f"{m.name}{m.signature}  # property", "```", ""]
    else:
        out += ["```python", _fit(m.name, m.signature), "```", ""]
    out += render_doc(parse_doc(m.doc), linker, m.params, cls)
    return out


def render_module(mod: Module, linker: Linker, modules) -> str:
    out = [f"# {mod.title}", ""]
    if mod.stem != "__init__":
        out += [f"Module `{mod.dotted}`. Generated from its docstrings by `tools/gen_py_docs.py`.", ""]
    out += render_doc(parse_doc(mod.doc), linker)
    if mod.stem == "__init__":
        out += render_index(modules, linker)
    for cls in mod.classes:
        out += render_class(cls, linker)
    for fn in mod.functions:
        out += render_member(fn, linker)
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).strip("\n") + "\n"


def render_index(modules, linker: Linker) -> list:
    out = [
        "## Reference Pages",
        "",
        "These pages are generated from the package's docstrings by `tools/gen_py_docs.py`. "
        "[Python Bindings](page:python) covers installing the package and how a Python game is put together.",
        "",
        "| Page | Covers |",
        "|---|---|",
    ]
    for mod in modules:
        if mod.stem == "__init__":
            continue
        summary = parse_doc(mod.doc).description.split("\n\n", 1)[0]
        names = [c.name for c in mod.classes] or [f.name for f in mod.functions]
        covers = ", ".join(f"`{n}`" for n in names[:6]) + (", ..." if len(names) > 6 else "")
        out.append(f"| [{mod.title}](page:{mod.slug}) | {cell(summary)} {covers} |")
    out.append("")
    return out


def generate() -> dict:
    modules = [load_module(stem, title) for stem, title in MODULES]
    linker = Linker(modules)
    pages = {}
    for mod in modules:
        name = "index.md" if mod.stem == "__init__" else f"{mod.stem}.md"
        pages[name] = render_module(mod, linker, modules)
    return pages


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--check", action="store_true", help="exit 1 if any page is missing or out of date")
    args = parser.parse_args()

    pages = generate()
    stale = []
    for name, text in pages.items():
        path = OUT_DIR / name
        if path.exists() and path.read_text() == text:
            continue
        stale.append(name)
        if not args.check:
            OUT_DIR.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
    extra = sorted(p.name for p in OUT_DIR.glob("*.md") if p.name not in pages) if OUT_DIR.exists() else []

    if args.check:
        if stale or extra:
            print(f"Python API pages out of date: {', '.join(stale + extra)}. Run tools/gen_py_docs.py.", file=sys.stderr)
            return 1
        return 0
    for name in extra:
        (OUT_DIR / name).unlink()
    print(f"Python API docs: {len(pages)} pages, {len(stale)} updated, {len(extra)} removed, in {OUT_DIR.relative_to(REPO)}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
