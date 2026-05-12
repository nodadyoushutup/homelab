"""Structure-aware chunking for Python, XML, JS/TS, Markdown, JSON, CSV, and many additional text languages."""
from __future__ import annotations

import ast
import json
import logging
import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from chunks.text import chunk_text

log = logging.getLogger(__name__)

_META_STR_MAX = 900


def _truncate(s: str, n: int = _META_STR_MAX) -> str:
    if not s:
        return ""
    s = s.strip()
    if len(s) <= n:
        return s
    return s[: n - 1] + "…"


def _env_int(name: str, default: int) -> int:
    try:
        return int(os.getenv(name, str(default)).strip())
    except ValueError:
        return default


def structured_strategy_for_path(rel_norm: str) -> str | None:
    lower = rel_norm.lower()
    base = Path(lower).name
    if base in ("dockerfile", "containerfile"):
        return "ast_dockerfile"
    if lower.endswith(".py"):
        return "ast_py"
    if lower.endswith(".xml"):
        return "ast_xml"
    if lower.endswith((".js", ".mjs", ".cjs", ".jsx", ".ts", ".tsx")):
        return "ast_js"
    if lower.endswith((".md", ".mdx")):
        return "ast_md"
    if lower.endswith(".json"):
        return "ast_json"
    if lower.endswith(".ipynb"):
        return "ast_ipynb"
    if lower.endswith(".csv"):
        return "ast_csv"
    if lower.endswith(".go"):
        return "ast_go"
    if lower.endswith(".rs"):
        return "ast_rust"
    if lower.endswith(".java"):
        return "ast_java"
    if lower.endswith(".c"):
        return "ast_c"
    if lower.endswith((".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".hxx")):
        return "ast_cxx"
    if lower.endswith(".cs"):
        return "ast_cs"
    if lower.endswith((".kt", ".kts")):
        return "ast_kt"
    if lower.endswith(".scala"):
        return "ast_scala"
    if lower.endswith(".swift"):
        return "ast_swift"
    if lower.endswith(".zig"):
        return "ast_zig"
    if lower.endswith((".m", ".mm")):
        return "ast_objc"
    if lower.endswith(".groovy"):
        return "ast_groovy"
    if lower.endswith((".sh", ".bash", ".zsh")):
        return "ast_sh"
    if lower.endswith((".tf", ".tfvars", ".hcl")):
        return "ast_hcl"
    if lower.endswith(".nix"):
        return "ast_nix"
    if lower.endswith((".yaml", ".yml")):
        return "ast_yaml"
    if lower.endswith(".toml"):
        return "ast_toml"
    if lower.endswith((".ini", ".cfg")):
        return "ast_ini"
    if lower.endswith(".sql"):
        return "ast_sql"
    if lower.endswith((".graphql", ".gql")):
        return "ast_graphql"
    if lower.endswith(".proto"):
        return "ast_proto"
    if lower.endswith(".vue"):
        return "ast_vue"
    if lower.endswith(".svelte"):
        return "ast_svelte"
    if lower.endswith(".astro"):
        return "ast_astro"
    if lower.endswith(".css"):
        return "ast_css"
    if lower.endswith(".scss"):
        return "ast_scss"
    if lower.endswith((".sass",)):
        return "ast_sass"
    if lower.endswith(".less"):
        return "ast_less"
    if lower.endswith(".php"):
        return "ast_php"
    if lower.endswith(".rb"):
        return "ast_ruby"
    if lower.endswith(".dart"):
        return "ast_dart"
    if lower.endswith((".clj", ".cljs", ".cljc")):
        return "ast_clojure"
    if lower.endswith((".fs", ".fsx")):
        return "ast_fsharp"
    if lower.endswith(".vb"):
        return "ast_vbnet"
    return None


@dataclass
class StructuredChunk:
    """One logical unit to embed; ``document`` is stored in Chroma as the text."""

    document: str
    start_line: int
    end_line: int
    language: str
    chunk_kind: str
    symbol: str = ""
    parent_symbol: str = ""
    odoo_name: str = ""
    odoo_inherit: str = ""
    odoo_inherits: str = ""
    decorators: str = ""
    python_bases: str = ""
    xml_tag: str = ""
    xml_model: str = ""
    xml_id: str = ""
    md_heading_level: int = 0
    md_heading_text: str = ""
    md_block_types: str = ""
    pdf_page: int = 0
    pdf_fusion: str = ""
    pdf_ingest_profile: str = ""
    json_pointer: str = ""
    json_top_key: str = ""
    tabular_sheet: str = ""
    tabular_row_start: int = 0
    tabular_row_end: int = 0
    tabular_headers: str = ""
    tabular_ingest_profile: str = ""
    office_part: str = ""
    office_index: int = 0
    office_ingest_profile: str = ""

    def extra_metadata(self) -> dict[str, Any]:
        core: dict[str, Any] = {
            "language": self.language,
            "chunk_kind": self.chunk_kind,
            "start_line": int(self.start_line),
            "end_line": int(self.end_line),
            "symbol": _truncate(self.symbol, 480),
            "parent_symbol": _truncate(self.parent_symbol, 240),
            "odoo_name": _truncate(self.odoo_name, 240),
            "odoo_inherit": _truncate(self.odoo_inherit, 480),
            "odoo_inherits": _truncate(self.odoo_inherits, 900),
            "decorators": _truncate(self.decorators, 480),
            "python_bases": _truncate(self.python_bases, 480),
            "xml_tag": _truncate(self.xml_tag, 120),
            "xml_model": _truncate(self.xml_model, 240),
            "xml_id": _truncate(self.xml_id, 240),
        }
        if self.language == "markdown":
            core["md_heading_level"] = int(self.md_heading_level)
            if self.md_heading_text:
                core["md_heading_text"] = _truncate(self.md_heading_text, 480)
            if self.md_block_types:
                core["md_block_types"] = _truncate(self.md_block_types, 480)
        if self.language == "pdf":
            core["pdf_page"] = int(self.pdf_page)
            if self.pdf_fusion:
                core["pdf_fusion"] = _truncate(self.pdf_fusion, 64)
            if self.pdf_ingest_profile:
                core["pdf_ingest_profile"] = _truncate(self.pdf_ingest_profile, 160)
        if self.language == "json":
            core["json_pointer"] = _truncate(self.json_pointer or "$", 240)
            if self.json_top_key:
                core["json_top_key"] = _truncate(self.json_top_key, 240)
        if self.language in ("csv", "xlsx"):
            if self.tabular_ingest_profile:
                core["tabular_ingest_profile"] = _truncate(self.tabular_ingest_profile, 200)
            if self.tabular_sheet:
                core["tabular_sheet"] = _truncate(self.tabular_sheet, 120)
            if self.tabular_headers:
                core["tabular_headers"] = _truncate(self.tabular_headers, 480)
            core["tabular_row_start"] = int(self.tabular_row_start)
            core["tabular_row_end"] = int(self.tabular_row_end)
        if self.language in ("docx", "pptx", "odt"):
            if self.office_ingest_profile:
                core["office_ingest_profile"] = _truncate(self.office_ingest_profile, 200)
            if self.office_part:
                core["office_part"] = _truncate(self.office_part, 120)
            core["office_index"] = int(self.office_index)
        return core


def _build_header(
    rel_path: str,
    *,
    language: str,
    chunk_kind: str,
    symbol: str = "",
    parent_symbol: str = "",
    odoo_name: str = "",
    odoo_inherit: str = "",
    odoo_inherits: str = "",
    decorators: str = "",
    python_bases: str = "",
    xml_tag: str = "",
    xml_model: str = "",
    xml_id: str = "",
    md_heading_level: int = 0,
    md_heading_text: str = "",
    md_block_types: str = "",
    json_pointer: str = "",
    json_top_key: str = "",
    tabular_sheet: str = "",
    tabular_row_start: int = 0,
    tabular_row_end: int = 0,
    tabular_headers: str = "",
    tabular_ingest_profile: str = "",
    office_part: str = "",
    office_index: int = 0,
    office_ingest_profile: str = "",
) -> str:
    parts = [
        f"[path:{rel_path}]",
        f"[lang:{language}]",
        f"[kind:{chunk_kind}]",
    ]
    if symbol:
        parts.append(f"[sym:{symbol}]")
    if parent_symbol:
        parts.append(f"[parent:{parent_symbol}]")
    if odoo_name:
        parts.append(f"[_name:{odoo_name}]")
    if odoo_inherit:
        parts.append(f"[_inherit:{odoo_inherit}]")
    if odoo_inherits:
        parts.append(f"[_inherits:{odoo_inherits}]")
    if decorators:
        parts.append(f"[decorators:{decorators}]")
    if python_bases:
        parts.append(f"[bases:{python_bases}]")
    if xml_tag:
        parts.append(f"[xml_tag:{xml_tag}]")
    if xml_model:
        parts.append(f"[xml_model:{xml_model}]")
    if xml_id:
        parts.append(f"[xml_id:{xml_id}]")
    if md_heading_level:
        parts.append(f"[md_hlevel:{md_heading_level}]")
    if md_heading_text:
        parts.append(f"[md_htext:{_truncate(md_heading_text, 200)}]")
    if md_block_types:
        parts.append(f"[md_blocks:{_truncate(md_block_types, 240)}]")
    if json_pointer:
        parts.append(f"[json_ptr:{_truncate(json_pointer, 200)}]")
    if json_top_key:
        parts.append(f"[json_key:{_truncate(json_top_key, 200)}]")
    if tabular_sheet:
        parts.append(f"[sheet:{_truncate(tabular_sheet, 80)}]")
    if tabular_row_start > 0 and tabular_row_end > 0:
        parts.append(f"[rows:{tabular_row_start}-{tabular_row_end}]")
    if tabular_headers:
        parts.append(f"[cols:{_truncate(tabular_headers, 200)}]")
    if office_part:
        parts.append(f"[office:{_truncate(office_part, 80)}:{office_index}]")
    return " ".join(parts)


def _lines_slice(source: str, start_line: int, end_line: int) -> str:
    lines = source.splitlines(keepends=True)
    if start_line < 1:
        start_line = 1
    if end_line < start_line:
        end_line = start_line
    chunk = "".join(lines[start_line - 1 : end_line])
    return chunk.rstrip() + ("\n" if chunk and not chunk.endswith("\n") else "")


def _node_end_lineno(node: ast.AST) -> int:
    end = getattr(node, "end_lineno", None)
    if isinstance(end, int) and end > 0:
        return end
    best = getattr(node, "lineno", 1) or 1
    for child in ast.iter_child_nodes(node):
        best = max(best, _node_end_lineno(child))
    return best


def _ast_literal_summary(node: ast.AST | None) -> str:
    if node is None:
        return ""
    if isinstance(node, ast.Constant):
        if isinstance(node.value, str):
            return node.value
        if node.value is None:
            return ""
        return str(node.value)
    if isinstance(node, ast.Str):  # pragma: no cover - py37
        return node.s
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, (ast.Tuple, ast.List)):
        parts = [_ast_literal_summary(x) for x in node.elts]
        return ",".join(p for p in parts if p)
    if isinstance(node, ast.Dict):
        parts: list[str] = []
        for k, v in zip(node.keys, node.values):
            if k is None or v is None:
                continue
            ks = _ast_literal_summary(k)
            vs = _ast_literal_summary(v)
            if ks and vs:
                parts.append(f"{ks}:{vs}")
        return ";".join(parts)[:800]
    return ""


def _format_decorators(decs: list[ast.expr]) -> str:
    out: list[str] = []

    def one(d: ast.expr) -> str:
        if isinstance(d, ast.Name):
            return d.id
        if isinstance(d, ast.Attribute):
            base = one(d.value) if isinstance(d.value, (ast.Name, ast.Attribute)) else "?"
            return f"{base}.{d.attr}"
        if isinstance(d, ast.Call):
            inner = one(d.func)
            return f"{inner}(...)"
        return type(d).__name__

    for d in decs:
        s = one(d)
        if s:
            out.append(s)
    return ",".join(out)


def _format_bases(bases: list[ast.expr]) -> str:
    names: list[str] = []

    def base_name(b: ast.expr) -> str:
        if isinstance(b, ast.Name):
            return b.id
        if isinstance(b, ast.Attribute):
            return f"{base_name(b.value)}.{b.attr}"
        if isinstance(b, ast.Subscript):
            return f"{base_name(b.value)}[...]"
        return ""

    for b in bases:
        n = base_name(b)
        if n:
            names.append(n)
    return ",".join(names)


def _class_odoo_fields(class_body: list[ast.stmt]) -> tuple[str, str, str]:
    name = inherit = inherits = ""
    for node in class_body:
        if isinstance(node, ast.Assign):
            for t in node.targets:
                if isinstance(t, ast.Name):
                    if t.id == "_name":
                        name = _ast_literal_summary(node.value)
                    elif t.id == "_inherit":
                        inherit = _ast_literal_summary(node.value)
                    elif t.id == "_inherits":
                        inherits = _ast_literal_summary(node.value)
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if node.target.id == "_name" and node.value:
                name = _ast_literal_summary(node.value)
            elif node.target.id == "_inherit" and node.value:
                inherit = _ast_literal_summary(node.value)
            elif node.target.id == "_inherits" and node.value:
                inherits = _ast_literal_summary(node.value)
    return name, inherit, inherits


def _meta_from_header_kwargs(header_kwargs: dict[str, Any]) -> dict[str, Any]:
    keys = frozenset(StructuredChunk.__dataclass_fields__) - {
        "document",
        "start_line",
        "end_line",
        "language",
        "chunk_kind",
        "symbol",
    }
    return {k: header_kwargs[k] for k in keys if k in header_kwargs and header_kwargs[k]}


def _split_oversized(
    rel_path: str,
    language: str,
    chunk_kind: str,
    symbol: str,
    body: str,
    start_line: int,
    *,
    max_chars: int,
    overlap: int,
    header_kwargs: dict[str, Any],
) -> list[StructuredChunk]:
    meta = _meta_from_header_kwargs(header_kwargs)
    if len(body) <= max_chars:
        hdr = _build_header(rel_path, language=language, chunk_kind=chunk_kind, symbol=symbol, **header_kwargs)
        doc = hdr + "\n" + body
        end_line = start_line + body.count("\n")
        return [
            StructuredChunk(
                document=doc,
                start_line=start_line,
                end_line=max(start_line, end_line),
                language=language,
                chunk_kind=chunk_kind,
                symbol=symbol,
                **meta,
            )
        ]
    hdr = _build_header(rel_path, language=language, chunk_kind=chunk_kind, symbol=symbol, **header_kwargs)
    pieces = chunk_text(body, max_chars, overlap)
    out: list[StructuredChunk] = []
    line_cursor = start_line
    for i, piece in enumerate(pieces):
        delta = piece.count("\n")
        end_l = line_cursor + delta
        doc = hdr + f" [part:{i + 1}/{len(pieces)}]\n" + piece
        out.append(
            StructuredChunk(
                document=doc,
                start_line=line_cursor,
                end_line=max(line_cursor, end_l),
                language=language,
                chunk_kind=f"{chunk_kind}_part",
                symbol=f"{symbol}#p{i}" if symbol else f"p{i}",
                **meta,
            )
        )
        line_cursor = max(line_cursor, end_l)
    return out


def chunks_python(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    try:
        tree = ast.parse(source)
    except SyntaxError as exc:
        log.info("python parse fallback for %s: %s", rel_path, exc)
        return []

    out: list[StructuredChunk] = []

    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            start, end = node.lineno, _node_end_lineno(node)
            body = _lines_slice(source, start, end)
            dec = _format_decorators(node.decorator_list)
            hdr_kw: dict[str, Any] = {
                "decorators": dec,
            }
            sym = node.name
            out.extend(
                _split_oversized(
                    rel_path,
                    "python",
                    "module_function",
                    sym,
                    body,
                    start,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
        elif isinstance(node, ast.ClassDef):
            odoo_name, odoo_inherit, odoo_inherits = _class_odoo_fields(node.body)
            bases = _format_bases(node.bases)
            dec = _format_decorators(node.decorator_list)
            hdr_kw = {
                "odoo_name": odoo_name,
                "odoo_inherit": odoo_inherit,
                "odoo_inherits": odoo_inherits,
                "decorators": dec,
                "python_bases": bases,
            }
            methods = [n for n in node.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]
            first_m = min((m.lineno for m in methods), default=None)
            if first_m is not None and first_m > node.lineno:
                h_end = first_m - 1
                header_src = _lines_slice(source, node.lineno, h_end).strip()
                if header_src:
                    doc = (
                        _build_header(
                            rel_path,
                            language="python",
                            chunk_kind="class_header",
                            symbol=node.name,
                            parent_symbol="",
                            **hdr_kw,
                        )
                        + "\n"
                        + header_src
                    )
                    out.append(
                        StructuredChunk(
                            document=doc,
                            start_line=node.lineno,
                            end_line=h_end,
                            language="python",
                            chunk_kind="class_header",
                            symbol=node.name,
                            odoo_name=odoo_name,
                            odoo_inherit=odoo_inherit,
                            odoo_inherits=odoo_inherits,
                            decorators=dec,
                            python_bases=bases,
                        )
                    )
            elif not methods:
                start, end = node.lineno, _node_end_lineno(node)
                body = _lines_slice(source, start, end)
                out.extend(
                    _split_oversized(
                        rel_path,
                        "python",
                        "class",
                        node.name,
                        body,
                        start,
                        max_chars=max_chars,
                        overlap=overlap,
                        header_kwargs=hdr_kw,
                    )
                )
            for m in methods:
                start, end = m.lineno, _node_end_lineno(m)
                body = _lines_slice(source, start, end)
                mdec = _format_decorators(m.decorator_list)
                comb_dec = ",".join(x for x in (dec, mdec) if x)
                m_kw = {**hdr_kw, "decorators": comb_dec, "parent_symbol": node.name}
                sym = f"{node.name}.{m.name}"
                out.extend(
                    _split_oversized(
                        rel_path,
                        "python",
                        "method",
                        sym,
                        body,
                        start,
                        max_chars=max_chars,
                        overlap=overlap,
                        header_kwargs=m_kw,
                    )
                )

    return out


def _md_walk_tokens(tokens: list[Any] | None):
    if not tokens:
        return
    for t in tokens:
        yield t
        ch = getattr(t, "children", None)
        if ch:
            yield from _md_walk_tokens(ch)


def _md_inline_text(children: list[Any] | None) -> str:
    if not children:
        return ""
    parts: list[str] = []
    for t in children:
        typ = t.type
        if typ == "text":
            parts.append(t.content or "")
        elif typ == "code_inline":
            parts.append(f"`{t.content or ''}`")
        elif typ in ("softbreak", "hardbreak"):
            parts.append(" ")
        elif typ in (
            "link_open",
            "link_close",
            "em_open",
            "em_close",
            "s_open",
            "s_close",
            "strong_open",
            "strong_close",
            "del_open",
            "del_close",
        ):
            continue
        elif typ == "html_inline":
            parts.append(t.content or "")
        elif getattr(t, "children", None):
            parts.append(_md_inline_text(t.children))
    return "".join(parts)


def _md_max_section_heading_level() -> int:
    """Headings deeper than this do not start a new chunk (stay inside the parent section)."""
    return max(1, min(6, _env_int("RAG_MD_MAX_SECTION_HEADING_LEVEL", 2)))


def _md_collect_headings(tokens: list[Any]) -> list[dict[str, Any]]:
    """Walk top-level tokens; inline lives between ``heading_open`` and ``heading_close``."""
    out: list[dict[str, Any]] = []
    i = 0
    n = len(tokens)
    while i < n:
        t = tokens[i]
        if t.type != "heading_open":
            i += 1
            continue
        tag = t.tag or ""
        if len(tag) < 2 or tag[0] != "h":
            i += 1
            continue
        try:
            level = int(tag[1])
        except ValueError:
            i += 1
            continue
        line = t.map[0] + 1 if t.map is not None else 1
        i += 1
        inline_buf: list[Any] = []
        while i < n and tokens[i].type != "heading_close":
            inline_buf.append(tokens[i])
            i += 1
        if i < n and tokens[i].type == "heading_close":
            i += 1
        title = _md_inline_text(inline_buf).strip()
        out.append({"line": line, "level": level, "title": title})
    return out


def _md_section_ranges(
    headings: list[dict[str, Any]],
    n_lines: int,
) -> list[tuple[int, int, dict[str, Any] | None]]:
    if n_lines < 1:
        n_lines = 1
    cap = _md_max_section_heading_level()
    filtered = [h for h in headings if int(h["level"]) <= cap]
    if not filtered and headings:
        filtered = list(headings)
    headings = filtered
    if not headings:
        return [(1, n_lines, None)]
    sections: list[tuple[int, int, dict[str, Any] | None]] = []
    if headings[0]["line"] > 1:
        sections.append((1, headings[0]["line"] - 1, None))
    for i, h in enumerate(headings):
        start = int(h["line"])
        hl = int(h["level"])
        end = n_lines
        for j in range(i + 1, len(headings)):
            if int(headings[j]["level"]) <= hl:
                end = int(headings[j]["line"]) - 1
                break
        if start <= end:
            sections.append((start, end, h))
    return sections


def _md_norm_block_tag(token: Any) -> str | None:
    typ = token.type
    if typ == "fence":
        return "code_fence"
    if typ == "heading_open":
        return "heading"
    if typ == "bullet_list_open":
        return "bullet_list"
    if typ == "ordered_list_open":
        return "ordered_list"
    if typ == "blockquote_open":
        return "blockquote"
    if typ == "paragraph_open":
        return "paragraph"
    if typ == "html_block":
        return "html_block"
    if typ == "table_open":
        return "table"
    if typ == "hr":
        return "hr"
    if typ == "list_item_open":
        return "list_item"
    return None


def _md_block_types_overlapping(tokens: list[Any], start_ln: int, end_ln: int) -> str:
    found: list[str] = []
    seen: set[str] = set()
    for t in _md_walk_tokens(tokens):
        m = getattr(t, "map", None)
        if not m or len(m) < 2:
            continue
        if m[1] <= m[0]:
            continue
        lo = m[0] + 1
        hi = m[1]
        if hi < start_ln or lo > end_ln:
            continue
        tag = _md_norm_block_tag(t)
        if tag and tag not in seen:
            seen.add(tag)
            found.append(tag)
    return ",".join(found)


def chunks_markdown(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    try:
        from markdown_it import MarkdownIt
    except ImportError:
        log.warning("markdown-it-py missing; markdown chunking disabled for %s", rel_path)
        return []
    if not source.strip():
        return []
    md = MarkdownIt("commonmark")
    try:
        token_list = md.parse(source)
    except Exception as exc:
        log.info("markdown parse failed for %s: %s", rel_path, exc)
        return []
    n_lines = len(source.splitlines())
    if n_lines < 1:
        n_lines = 1
    headings = _md_collect_headings(token_list)
    ranges = _md_section_ranges(headings, n_lines)
    out: list[StructuredChunk] = []
    for start_ln, end_ln, h in ranges:
        if start_ln > end_ln:
            continue
        body = _lines_slice(source, start_ln, end_ln).strip()
        if not body:
            continue
        md_types = _md_block_types_overlapping(token_list, start_ln, end_ln)
        if h:
            chunk_kind = "md_section"
            title = (h.get("title") or "").strip()
            level = int(h.get("level") or 0)
            sym = title or f"h{level}"
        else:
            chunk_kind = "md_preamble"
            title = ""
            level = 0
            sym = "preamble"
        hdr_kw: dict[str, Any] = {
            "md_heading_level": level,
            "md_heading_text": title,
            "md_block_types": md_types,
        }
        out.extend(
            _split_oversized(
                rel_path,
                "markdown",
                chunk_kind,
                sym,
                body + "\n",
                start_ln,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def _local_xml_tag(tag: str | bytes) -> str:
    if isinstance(tag, str):
        if tag.startswith("{"):
            return tag.rsplit("}", 1)[-1]
        return tag
    return ""


def chunks_xml(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    try:
        from lxml import etree
    except ImportError:
        log.warning("lxml missing; XML structured chunking disabled for %s", rel_path)
        return []

    parser = etree.XMLParser(recover=True, huge_tree=True, remove_blank_text=False)
    try:
        root = etree.fromstring(source.encode("utf-8"), parser)
    except etree.XMLSyntaxError as exc:
        log.info("xml parse fallback for %s: %s", rel_path, exc)
        return []

    out: list[StructuredChunk] = []

    def emit_element(el: Any, chunk_kind: str) -> None:
        tag = _local_xml_tag(el.tag)
        if not tag:
            return
        try:
            blob = etree.tostring(el, encoding="unicode", pretty_print=False)
        except Exception:
            return
        sl = int(getattr(el, "sourceline", None) or 1)
        model = el.get("model", "") or ""
        xml_id = el.get("id", "") or ""
        hdr_kw: dict[str, Any] = {
            "xml_tag": tag,
            "xml_model": model,
            "xml_id": xml_id,
        }
        sym = xml_id or f"{tag}:{model}" if model else tag
        out.extend(
            _split_oversized(
                rel_path,
                "xml",
                chunk_kind,
                sym,
                blob.strip() + "\n",
                sl,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )

    def walk(el: Any) -> None:
        tag = _local_xml_tag(el.tag)
        if tag in {"record", "template"}:
            emit_element(el, f"xml_{tag}")
            return
        if tag == "xpath":
            parent = el.getparent()
            pt = _local_xml_tag(parent.tag) if parent is not None else ""
            if pt in {"data", "odoo", "openerp"} or parent is None:
                emit_element(el, "xml_xpath")
            return
        for child in el:
            if isinstance(child.tag, str):
                walk(child)

    rtag = _local_xml_tag(root.tag)
    if rtag in {"odoo", "openerp", "data"}:
        for child in root:
            if isinstance(child.tag, str):
                walk(child)
    else:
        walk(root)

    return out


def chunks_javascript(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    from chunks.tree_sitter import chunks_javascript_ts

    return chunks_javascript_ts(rel_path, source, max_chars=max_chars, overlap=overlap)


def _json_key_start_line(source: str, key: str) -> int:
    if not key:
        return 1
    for pattern in (f'"{key}"', f"'{key}'"):
        idx = source.find(pattern)
        if idx >= 0:
            return source.count("\n", 0, idx) + 1
    return 1


def _json_dumps_fragment(obj: Any) -> str:
    return json.dumps(obj, ensure_ascii=False, indent=2)


def chunks_json(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    """Chunk JSON by top-level keys (objects) or index windows (arrays); small files stay one root chunk."""
    src = source.strip()
    if not src:
        return []
    try:
        data = json.loads(src)
    except json.JSONDecodeError as exc:
        log.info("json parse fallback for %s: %s", rel_path, exc)
        return []

    cap = max(512, max_chars)
    out: list[StructuredChunk] = []

    def emit_body(
        body: str,
        *,
        chunk_kind: str,
        symbol: str,
        start_line: int,
        ptr: str,
        top_key: str,
    ) -> None:
        hdr_kw: dict[str, Any] = {
            "json_pointer": ptr,
            "json_top_key": top_key,
        }
        out.extend(
            _split_oversized(
                rel_path,
                "json",
                chunk_kind,
                symbol,
                body.rstrip() + "\n",
                start_line,
                max_chars=cap,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )

    pretty_full = _json_dumps_fragment(data)
    if len(pretty_full) <= cap:
        emit_body(
            pretty_full,
            chunk_kind="json_root",
            symbol="root",
            start_line=1,
            ptr="$",
            top_key="",
        )
        return out

    if isinstance(data, dict):
        for k in sorted(data.keys(), key=lambda x: str(x)):
            k_str = str(k)
            frag = {k: data[k]}
            body = _json_dumps_fragment(frag)
            sl = _json_key_start_line(source, k_str)
            ptr = "/" + k_str.replace("~", "~0").replace("/", "~1")
            emit_body(
                body,
                chunk_kind="json_key",
                symbol=k_str[:200],
                start_line=sl,
                ptr=ptr,
                top_key=k_str,
            )
        return out

    if isinstance(data, list):
        n = len(data)
        i = 0
        while i < n:
            batch: list[Any] = []
            batch_chars = 0
            start_i = i
            while i < n:
                one = _json_dumps_fragment(data[i])
                add_len = len(one) + 4
                if batch and batch_chars + add_len > cap:
                    break
                batch.append(data[i])
                batch_chars += add_len
                i += 1
                if len(batch) >= 80:
                    break
            body = _json_dumps_fragment(batch)
            end_i = i - 1
            ptr = f"/{start_i}-{end_i}" if start_i == end_i else f"/{start_i}:{end_i}"
            emit_body(
                body,
                chunk_kind="json_array_slice",
                symbol=f"items[{start_i}..{end_i}]",
                start_line=1,
                ptr=ptr,
                top_key="",
            )
        return out

    emit_body(
        pretty_full,
        chunk_kind="json_scalar",
        symbol="value",
        start_line=1,
        ptr="$",
        top_key="",
    )
    return out


def build_structured_chunks(rel_path: str, source: str) -> tuple[str | None, list[StructuredChunk]]:
    """Return (chunk_strategy or None, chunks). Empty list means caller should use char fallback."""
    from chunks import tree_sitter as tsl

    strat = structured_strategy_for_path(rel_path)
    if not strat:
        return None, []
    max_chars = max(512, _env_int("RAG_STRUCTURED_MAX_CHUNK_CHARS", 12000))
    overlap = max(0, _env_int("RAG_STRUCTURED_CHUNK_OVERLAP", 200))
    if strat == "ast_py":
        chunks = chunks_python(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_py", chunks) if chunks else (None, [])
    if strat == "ast_xml":
        chunks = chunks_xml(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_xml", chunks) if chunks else (None, [])
    if strat == "ast_js":
        chunks = chunks_javascript(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_js", chunks) if chunks else (None, [])
    if strat == "ast_md":
        chunks = chunks_markdown(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_md", chunks) if chunks else (None, [])
    if strat == "ast_json":
        chunks = chunks_json(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_json", chunks) if chunks else (None, [])
    if strat == "ast_ipynb":
        chunks = tsl.chunks_ipynb(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_ipynb", chunks) if chunks else (None, [])
    if strat == "ast_csv":
        from chunks.tabular import chunks_csv

        chunks = chunks_csv(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_csv", chunks) if chunks else (None, [])
    if strat in tsl.TS_STRATEGIES:
        chunks = tsl.chunks_registered_ts(rel_path, source, strategy=strat, max_chars=max_chars, overlap=overlap)
        return (strat, chunks) if chunks else (None, [])
    if strat == "ast_hcl":
        chunks = tsl.chunks_hcl_blocks(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_hcl", chunks) if chunks else (None, [])
    if strat == "ast_yaml":
        chunks = tsl.chunks_yaml_mapping(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_yaml", chunks) if chunks else (None, [])
    if strat == "ast_toml":
        chunks = tsl.chunks_toml_tables(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_toml", chunks) if chunks else (None, [])
    if strat == "ast_ini":
        chunks = tsl.chunks_ini(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_ini", chunks) if chunks else (None, [])
    if strat == "ast_sql":
        chunks = tsl.chunks_sql_statements(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_sql", chunks) if chunks else (None, [])
    if strat == "ast_graphql":
        chunks = tsl.chunks_graphql_definitions(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_graphql", chunks) if chunks else (None, [])
    if strat == "ast_proto":
        chunks = tsl.chunks_proto(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_proto", chunks) if chunks else (None, [])
    if strat == "ast_dockerfile":
        chunks = tsl.chunks_dockerfile_instructions(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_dockerfile", chunks) if chunks else (None, [])
    if strat == "ast_nix":
        chunks = tsl.chunks_nix_top_bindings(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_nix", chunks) if chunks else (None, [])
    if strat == "ast_svelte":
        chunks = tsl.chunks_svelte_blocks(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_svelte", chunks) if chunks else (None, [])
    if strat == "ast_vue":
        chunks = tsl.chunks_vue_sfc(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_vue", chunks) if chunks else (None, [])
    if strat == "ast_astro":
        chunks = tsl.chunks_astro(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_astro", chunks) if chunks else (None, [])
    if strat == "ast_css":
        chunks = tsl.chunks_stylesheet_rules(
            rel_path, source, module_name="tree_sitter_css", language_label="css", strategy_prefix="css", max_chars=max_chars, overlap=overlap
        )
        return ("ast_css", chunks) if chunks else (None, [])
    if strat == "ast_scss":
        chunks = tsl.chunks_stylesheet_rules(
            rel_path,
            source,
            module_name="tree_sitter_scss",
            language_label="scss",
            strategy_prefix="scss",
            max_chars=max_chars,
            overlap=overlap,
        )
        return ("ast_scss", chunks) if chunks else (None, [])
    if strat == "ast_sass":
        chunks = tsl.chunks_stylesheet_rules(
            rel_path,
            source,
            module_name="tree_sitter_scss",
            language_label="sass",
            strategy_prefix="sass",
            max_chars=max_chars,
            overlap=overlap,
        )
        return ("ast_sass", chunks) if chunks else (None, [])
    if strat == "ast_less":
        chunks = tsl.chunks_stylesheet_rules(
            rel_path,
            source,
            module_name="tree_sitter_less",
            language_label="less",
            strategy_prefix="less",
            max_chars=max_chars,
            overlap=overlap,
        )
        return ("ast_less", chunks) if chunks else (None, [])
    if strat == "ast_dart":
        from chunks.heuristic_lang import chunks_dart

        chunks = chunks_dart(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_dart", chunks) if chunks else (None, [])
    if strat == "ast_clojure":
        from chunks.heuristic_lang import chunks_clojure

        chunks = chunks_clojure(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_clojure", chunks) if chunks else (None, [])
    if strat == "ast_fsharp":
        from chunks.heuristic_lang import chunks_fsharp

        chunks = chunks_fsharp(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_fsharp", chunks) if chunks else (None, [])
    if strat == "ast_vbnet":
        from chunks.heuristic_lang import chunks_vbnet

        chunks = chunks_vbnet(rel_path, source, max_chars=max_chars, overlap=overlap)
        return ("ast_vbnet", chunks) if chunks else (None, [])
    return None, []


def index_schema_version() -> str:
    return (os.getenv("RAG_INDEX_SCHEMA_VERSION") or "3").strip()
