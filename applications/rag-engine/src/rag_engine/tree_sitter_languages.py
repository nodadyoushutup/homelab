"""Tree-sitter–based structured chunking for additional languages (same methodology as ``chunks_javascript``)."""
from __future__ import annotations

import importlib
import logging
import re
from typing import Any

from rag_engine.structured_chunks import StructuredChunk, _build_header, _split_oversized

log = logging.getLogger(__name__)

_PARSER_CACHE: dict[str, Any] = {}
_PARSER_FAILED: set[str] = set()

# Some PyPI grammars expose ``language_php`` instead of ``language``.
_MODULE_LANGUAGE_ATTR: dict[str, str] = {
    "tree_sitter_php": "language_php",
}

_ID_TYPES = frozenset(
    {
        "identifier",
        "type_identifier",
        "field_identifier",
        "simple_identifier",
        "property_identifier",
        "namespace_identifier",
    }
)


def _parser_for_module(module_name: str) -> Any | None:
    if module_name in _PARSER_FAILED:
        return None
    if module_name in _PARSER_CACHE:
        return _PARSER_CACHE[module_name]
    try:
        mod = importlib.import_module(module_name)
        attr = _MODULE_LANGUAGE_ATTR.get(module_name, "language")
        lang_fn = getattr(mod, attr, None)
        if not callable(lang_fn):
            lang_fn = getattr(mod, "language", None)
        if not callable(lang_fn):
            _PARSER_FAILED.add(module_name)
            return None
        from tree_sitter import Language, Parser

        lang = Language(lang_fn())
        try:
            p = Parser(lang)
        except TypeError:
            p = Parser()
            p.language = lang
        _PARSER_CACHE[module_name] = p
        return p
    except Exception as exc:
        log.info("tree-sitter module %s unavailable: %s", module_name, exc)
        _PARSER_FAILED.add(module_name)
        return None


def _first_identifier(source_b: bytes, node: Any) -> str:
    """Best-effort symbol from a declaration node (depth-first)."""
    stack = [node]
    while stack:
        n = stack.pop()
        if getattr(n, "type", None) in _ID_TYPES:
            return source_b[n.start_byte : n.end_byte].decode("utf-8", errors="replace")
        children = getattr(n, "children", None) or ()
        for c in reversed(list(children)):
            if getattr(c, "is_named", True):
                stack.append(c)
    return ""


def _collect_target_nodes(root: Any, target_types: frozenset[str]) -> list[Any]:
    out: list[Any] = []

    def visit(n: Any) -> None:
        t = n.type
        if t in target_types:
            out.append(n)
            return
        for c in n.children:
            visit(c)

    visit(root)
    return out


def chunks_by_target_types(
    rel_path: str,
    source: str,
    *,
    module_name: str,
    language_label: str,
    target_types: frozenset[str],
    chunk_kind_prefix: str,
    max_chars: int,
    overlap: int,
    whole_file_fallback: bool = False,
) -> list[StructuredChunk]:
    parser = _parser_for_module(module_name)
    if parser is None:
        return []
    source_b = source.encode("utf-8")
    try:
        tree = parser.parse(source_b)
    except Exception as exc:
        log.info("tree-sitter parse failed for %s: %s", rel_path, exc)
        return []

    targets = _collect_target_nodes(tree.root_node, target_types)
    if not targets and whole_file_fallback and source.strip():
        hdr = _build_header(rel_path, language=language_label, chunk_kind=f"{chunk_kind_prefix}_file", symbol="")
        doc = hdr + "\n" + source.strip() + "\n"
        return [
            StructuredChunk(
                document=doc,
                start_line=1,
                end_line=max(1, source.count("\n") + 1),
                language=language_label,
                chunk_kind=f"{chunk_kind_prefix}_file",
                symbol="",
            )
        ]
    if not targets:
        return []

    out: list[StructuredChunk] = []
    seen: set[tuple[int, int]] = set()
    for node in targets:
        key = (node.start_byte, node.end_byte)
        if key in seen:
            continue
        seen.add(key)
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace")
        start_line = node.start_point[0] + 1
        end_line = node.end_point[0] + 1
        sym = _first_identifier(source_b, node) or node.type
        kind = f"{chunk_kind_prefix}_{node.type}"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                kind,
                sym,
                body.strip() + "\n",
                start_line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_javascript_ts(
    rel_path: str, source: str, *, max_chars: int, overlap: int
) -> list[StructuredChunk]:
    return chunks_by_target_types(
        rel_path,
        source,
        module_name="tree_sitter_javascript",
        language_label="javascript",
        target_types=frozenset({"class_declaration", "function_declaration", "method_definition"}),
        chunk_kind_prefix="js",
        max_chars=max_chars,
        overlap=overlap,
    )


def chunks_hcl_blocks(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_hcl")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    blocks: list[Any] = []
    if root.type == "config_file" and root.children:
        body = root.children[0]
        if body.type == "body":
            for ch in body.children:
                if ch.type == "block":
                    blocks.append(ch)
    if not blocks:
        return []
    out: list[StructuredChunk] = []
    source_b = source.encode("utf-8")
    for node in blocks:
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace")
        start_line = node.start_point[0] + 1
        sym = _first_identifier(source_b, node) or "block"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "hcl",
                f"hcl_{node.type}",
                sym,
                body.strip() + "\n",
                start_line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_sql_statements(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_sql")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "program":
        return []
    stmts: list[Any] = []
    for ch in root.children:
        if ch.type == "statement":
            stmts.append(ch)
    if not stmts:
        if not source.strip():
            return []
        hdr_kw: dict[str, Any] = {}
        return _split_oversized(
            rel_path,
            "sql",
            "sql_file",
            "file",
            source.strip() + "\n",
            1,
            max_chars=max_chars,
            overlap=overlap,
            header_kwargs=hdr_kw,
        )
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    for i, node in enumerate(stmts):
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace").strip()
        if not body:
            continue
        inner = node.children[0] if node.children else node
        start_line = node.start_point[0] + 1
        sym = inner.type if inner else f"stmt_{i}"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "sql",
                "sql_statement",
                str(sym),
                body + "\n",
                start_line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_yaml_mapping(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_yaml")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "stream":
        return []
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    doc_idx = 0
    for doc_node in root.children:
        if doc_node.type != "document":
            continue
        doc_idx += 1
        mapping: Any | None = None
        for ch in doc_node.children:
            if ch.type == "block_node" and ch.children:
                inner = ch.children[0]
                if inner.type == "block_mapping":
                    mapping = inner
                    break
        if mapping is None:
            body = source_b[doc_node.start_byte : doc_node.end_byte].decode("utf-8", errors="replace")
            hdr_kw: dict[str, Any] = {}
            out.extend(
                _split_oversized(
                    rel_path,
                    "yaml",
                    "yaml_document",
                    f"doc{doc_idx}",
                    body.strip() + "\n",
                    doc_node.start_point[0] + 1,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
            continue
        pairs = [c for c in mapping.children if c.type == "block_mapping_pair"]
        if len(pairs) <= 1:
            body = source_b[doc_node.start_byte : doc_node.end_byte].decode("utf-8", errors="replace")
            hdr_kw = {}
            out.extend(
                _split_oversized(
                    rel_path,
                    "yaml",
                    "yaml_document",
                    f"doc{doc_idx}",
                    body.strip() + "\n",
                    doc_node.start_point[0] + 1,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
            continue
        for pair in pairs:
            key_s = "key"
            if pair.children:
                key_node = pair.children[0]
                key_s = source_b[key_node.start_byte : key_node.end_byte].decode("utf-8", errors="replace").strip()[:200] or "key"
            body = source_b[pair.start_byte : pair.end_byte].decode("utf-8", errors="replace")
            hdr_kw = {}
            sym = f"doc{doc_idx}:{key_s}"
            out.extend(
                _split_oversized(
                    rel_path,
                    "yaml",
                    "yaml_pair",
                    sym,
                    body.strip() + "\n",
                    pair.start_point[0] + 1,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
    return out


def chunks_toml_tables(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_toml")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "document":
        return []
    source_b = source.encode("utf-8")
    children = list(root.children)
    out: list[StructuredChunk] = []
    preamble: list[Any] = []
    i = 0
    while i < len(children) and children[i].type == "pair":
        preamble.append(children[i])
        i += 1
    if preamble:
        start_ln = preamble[0].start_point[0] + 1
        end_ln = preamble[-1].end_point[0] + 1
        body = source_b[preamble[0].start_byte : preamble[-1].end_byte].decode("utf-8", errors="replace")
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "toml",
                "toml_preamble",
                "preamble",
                body.strip() + "\n",
                start_ln,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    while i < len(children):
        node = children[i]
        if node.type == "table":
            body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace")
            sym = "table"
            for c in node.children:
                if c.type in ("bare_key", "dotted_key"):
                    sym = source_b[c.start_byte : c.end_byte].decode("utf-8", errors="replace").strip()[:200]
                    break
            hdr_kw = {}
            out.extend(
                _split_oversized(
                    rel_path,
                    "toml",
                    "toml_table",
                    sym,
                    body.strip() + "\n",
                    node.start_point[0] + 1,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
        i += 1
    return out


def chunks_dockerfile_instructions(
    rel_path: str, source: str, *, max_chars: int, overlap: int
) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_dockerfile")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "source_file":
        return []
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    for node in root.children:
        typ = node.type
        if typ == "comment" or typ.strip() == "":
            continue
        if not typ.endswith("_instruction"):
            continue
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace").strip()
        if not body:
            continue
        sym = typ.replace("_instruction", "")[:80]
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "dockerfile",
                f"dockerfile_{typ}",
                sym,
                body + "\n",
                node.start_point[0] + 1,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_graphql_definitions(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_graphql")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "source_file" or not root.children:
        return []
    doc = root.children[0]
    if doc.type != "document":
        return []
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    idx = 0
    for ch in doc.children:
        if ch.type != "definition":
            continue
        idx += 1
        body = source_b[ch.start_byte : ch.end_byte].decode("utf-8", errors="replace")
        sym = _first_identifier(source_b, ch) or f"def{idx}"
        hdr_kw: dict[str, Any] = {}
        out.extend(
            _split_oversized(
                rel_path,
                "graphql",
                "graphql_definition",
                sym,
                body.strip() + "\n",
                ch.start_point[0] + 1,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_svelte_blocks(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_svelte")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    doc = tree.root_node
    if doc.type != "document":
        return []
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    template_nodes: list[Any] = []

    def flush_template() -> None:
        if not template_nodes:
            return
        start_b = template_nodes[0].start_byte
        end_b = template_nodes[-1].end_byte
        body = source_b[start_b:end_b].decode("utf-8", errors="replace").strip()
        if body:
            start_ln = template_nodes[0].start_point[0] + 1
            hdr_kw: dict[str, Any] = {}
            out.extend(
                _split_oversized(
                    rel_path,
                    "svelte",
                    "svelte_template",
                    "template",
                    body + "\n",
                    start_ln,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
        template_nodes.clear()

    for ch in doc.children:
        if ch.type == "script_element":
            flush_template()
            body = source_b[ch.start_byte : ch.end_byte].decode("utf-8", errors="replace").strip()
            if body:
                hdr_kw = {}
                out.extend(
                    _split_oversized(
                        rel_path,
                        "svelte",
                        "svelte_script",
                        "script",
                        body + "\n",
                        ch.start_point[0] + 1,
                        max_chars=max_chars,
                        overlap=overlap,
                        header_kwargs=hdr_kw,
                    )
                )
        elif ch.type == "style_element":
            flush_template()
            body = source_b[ch.start_byte : ch.end_byte].decode("utf-8", errors="replace").strip()
            if body:
                hdr_kw = {}
                out.extend(
                    _split_oversized(
                        rel_path,
                        "svelte",
                        "svelte_style",
                        "style",
                        body + "\n",
                        ch.start_point[0] + 1,
                        max_chars=max_chars,
                        overlap=overlap,
                        header_kwargs=hdr_kw,
                    )
                )
        else:
            template_nodes.append(ch)
    flush_template()
    return out


def chunks_nix_top_bindings(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    parser = _parser_for_module("tree_sitter_nix")
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    if root.type != "source_code":
        return []

    def is_top_level_binding(node: Any) -> bool:
        if node.type != "binding":
            return False
        bs = node.parent
        if bs is None or bs.type != "binding_set":
            return False
        attr = bs.parent
        if attr is None or attr.type != "attrset_expression":
            return False
        src = attr.parent
        return src is not None and src.type == "source_code"

    bindings: list[Any] = []

    def walk(n: Any) -> None:
        if is_top_level_binding(n):
            bindings.append(n)
            return
        for c in n.children:
            walk(c)

    walk(root)
    if not bindings:
        return chunks_by_target_types(
            rel_path,
            source,
            module_name="tree_sitter_nix",
            language_label="nix",
            target_types=frozenset({"function_expression"}),
            chunk_kind_prefix="nix",
            max_chars=max_chars,
            overlap=overlap,
            whole_file_fallback=True,
        )
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    for node in bindings:
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace")
        sym = _first_identifier(source_b, node) or "binding"
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                "nix",
                "nix_binding",
                sym,
                body.strip() + ";\n",
                node.start_point[0] + 1,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_stylesheet_rules(
    rel_path: str,
    source: str,
    *,
    module_name: str,
    language_label: str,
    strategy_prefix: str,
    max_chars: int,
    overlap: int,
) -> list[StructuredChunk]:
    parser = _parser_for_module(module_name)
    if parser is None or not source.strip():
        return []
    tree = parser.parse(source.encode("utf-8"))
    root = tree.root_node
    targets = frozenset(
        {
            "rule_set",
            "media_statement",
            "import_statement",
            "at_rule",
            "keyframes_statement",
        }
    )
    nodes = _collect_target_nodes(root, targets)
    if not nodes:
        return chunks_by_target_types(
            rel_path,
            source,
            module_name=module_name,
            language_label=language_label,
            target_types=frozenset(),
            chunk_kind_prefix=strategy_prefix,
            max_chars=max_chars,
            overlap=overlap,
            whole_file_fallback=True,
        )
    source_b = source.encode("utf-8")
    out: list[StructuredChunk] = []
    seen: set[tuple[int, int]] = set()
    for node in nodes:
        key = (node.start_byte, node.end_byte)
        if key in seen:
            continue
        seen.add(key)
        body = source_b[node.start_byte : node.end_byte].decode("utf-8", errors="replace")
        start_line = node.start_point[0] + 1
        sym = node.type
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                f"{strategy_prefix}_{node.type}",
                sym,
                body.strip() + "\n",
                start_line,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


_TS_REGISTRY: dict[str, tuple[str, str, str, frozenset[str], bool]] = {
    "ast_go": ("tree_sitter_go", "go", "go", frozenset({"function_declaration", "method_declaration", "type_declaration"}), False),
    "ast_rust": (
        "tree_sitter_rust",
        "rust",
        "rust",
        frozenset({"function_item", "struct_item", "enum_item", "impl_item", "mod_item", "trait_item"}),
        False,
    ),
    "ast_java": (
        "tree_sitter_java",
        "java",
        "java",
        frozenset({"class_declaration", "interface_declaration", "enum_declaration", "record_declaration"}),
        False,
    ),
    "ast_c": ("tree_sitter_c", "c", "c", frozenset({"function_definition", "struct_specifier"}), False),
    "ast_cxx": (
        "tree_sitter_cpp",
        "cpp",
        "cpp",
        frozenset(
            {
                "namespace_definition",
                "class_specifier",
                "function_definition",
                "template_declaration",
            }
        ),
        False,
    ),
    "ast_cs": (
        "tree_sitter_c_sharp",
        "csharp",
        "cs",
        frozenset(
            {
                "class_declaration",
                "interface_declaration",
                "struct_declaration",
                "enum_declaration",
                "record_declaration",
            }
        ),
        False,
    ),
    "ast_kt": (
        "tree_sitter_kotlin",
        "kotlin",
        "kt",
        frozenset({"class_declaration", "object_declaration", "function_declaration"}),
        False,
    ),
    "ast_scala": (
        "tree_sitter_scala",
        "scala",
        "scala",
        frozenset({"class_definition", "object_definition", "trait_definition", "function_definition"}),
        False,
    ),
    "ast_swift": (
        "tree_sitter_swift",
        "swift",
        "swift",
        frozenset({"class_declaration", "function_declaration", "protocol_declaration"}),
        False,
    ),
    "ast_zig": (
        "tree_sitter_zig",
        "zig",
        "zig",
        frozenset({"function_declaration", "variable_declaration", "test_declaration"}),
        False,
    ),
    "ast_objc": (
        "tree_sitter_objc",
        "objc",
        "objc",
        frozenset({"class_interface", "class_implementation"}),
        False,
    ),
    "ast_groovy": (
        "tree_sitter_groovy",
        "groovy",
        "groovy",
        frozenset({"class_declaration", "function_definition", "enum_declaration"}),
        False,
    ),
    "ast_php": (
        "tree_sitter_php",
        "php",
        "php",
        frozenset({"class_declaration", "interface_declaration", "function_definition"}),
        False,
    ),
    "ast_ruby": (
        "tree_sitter_ruby",
        "ruby",
        "ruby",
        frozenset({"class", "module", "method"}),
        False,
    ),
    "ast_sh": (
        "tree_sitter_bash",
        "bash",
        "sh",
        frozenset({"function_definition"}),
        True,
    ),
}

TS_STRATEGIES = frozenset(_TS_REGISTRY.keys())


def chunks_registered_ts(
    rel_path: str, source: str, *, strategy: str, max_chars: int, overlap: int
) -> list[StructuredChunk]:
    row = _TS_REGISTRY.get(strategy)
    if not row:
        return []
    mod, label, prefix, types, fallback = row
    return chunks_by_target_types(
        rel_path,
        source,
        module_name=mod,
        language_label=label,
        target_types=types,
        chunk_kind_prefix=prefix,
        max_chars=max_chars,
        overlap=overlap,
        whole_file_fallback=fallback,
    )


_SFC_BLOCK = re.compile(
    r"<(?P<tag>script|style)\b[^>]*>(?P<body>[\s\S]*?)</(?P=tag)>",
    re.IGNORECASE,
)


def chunks_vue_sfc(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    return _chunks_sfc_generic(rel_path, source, language_label="vue", strategy_prefix="vue", max_chars=max_chars, overlap=overlap)


def chunks_astro(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    return _chunks_sfc_generic(
        rel_path, source, language_label="astro", strategy_prefix="astro", max_chars=max_chars, overlap=overlap
    )


def _chunks_sfc_generic(
    rel_path: str,
    source: str,
    *,
    language_label: str,
    strategy_prefix: str,
    max_chars: int,
    overlap: int,
) -> list[StructuredChunk]:
    if not source.strip():
        return []
    out: list[StructuredChunk] = []
    cursor = 0
    if language_label == "astro" and source.lstrip().startswith("---"):
        i = source.find("---")
        j = source.find("\n---", i + 3)
        if j != -1:
            fm = source[i + 3 : j].strip()
            if fm:
                hdr_kw: dict[str, Any] = {}
                out.extend(
                    _split_oversized(
                        rel_path,
                        language_label,
                        f"{strategy_prefix}_frontmatter",
                        "frontmatter",
                        fm + "\n",
                        1,
                        max_chars=max_chars,
                        overlap=overlap,
                        header_kwargs=hdr_kw,
                    )
                )
            cursor = j + len("\n---")
    n = len(source)
    for m in _SFC_BLOCK.finditer(source[cursor:]):
        abs_start = cursor + m.start()
        abs_end = cursor + m.end()
        pre = source[cursor:abs_start].strip()
        if pre:
            hdr_kw = {}
            line0 = source.count("\n", 0, cursor) + 1
            out.extend(
                _split_oversized(
                    rel_path,
                    language_label,
                    f"{strategy_prefix}_template",
                    "template",
                    pre + "\n",
                    line0,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
        tag = (m.group("tag") or "").lower()
        body_full = m.group(0) or ""
        line_start = source.count("\n", 0, abs_start) + 1
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                f"{strategy_prefix}_{tag}",
                tag,
                body_full.strip() + "\n",
                line_start,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
        cursor = abs_end
    tail = source[cursor:].strip()
    if tail:
        line0 = source.count("\n", 0, cursor) + 1
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                f"{strategy_prefix}_template",
                "template",
                tail + "\n",
                line0,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    if not out and source.strip():
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                language_label,
                f"{strategy_prefix}_file",
                "file",
                source.strip() + "\n",
                1,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


_PROTO_BLOCK_START = re.compile(
    r"(?m)^\s*(?P<kw>syntax|package|import|option|message|service|enum|extend|rpc|oneof|reserved)\b\s+"
)


def chunks_proto(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    if not source.strip():
        return []
    matches = list(_PROTO_BLOCK_START.finditer(source))
    if not matches:
        hdr = _build_header(rel_path, language="protobuf", chunk_kind="proto_file", symbol="")
        doc = hdr + "\n" + source.strip() + "\n"
        return [
            StructuredChunk(
                document=doc,
                start_line=1,
                end_line=max(1, source.count("\n") + 1),
                language="protobuf",
                chunk_kind="proto_file",
                symbol="",
            )
        ]
    out: list[StructuredChunk] = []
    for i, m in enumerate(matches):
        start = m.start()
        end = matches[i + 1].start() if i + 1 < len(matches) else len(source)
        body = source[start:end].strip()
        if not body:
            continue
        kw = (m.group("kw") or "block").strip()
        line_start = source.count("\n", 0, start) + 1
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                "protobuf",
                "proto_block",
                f"{kw}:{line_start}",
                body + "\n",
                line_start,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_ipynb(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    import json

    try:
        nb = json.loads(source)
    except json.JSONDecodeError as exc:
        log.info("ipynb json fallback for %s: %s", rel_path, exc)
        return []
    cells = nb.get("cells")
    if not isinstance(cells, list):
        return []
    out: list[StructuredChunk] = []
    for i, cell in enumerate(cells):
        if not isinstance(cell, dict):
            continue
        ctype = str(cell.get("cell_type") or "cell")
        src_parts = cell.get("source")
        if isinstance(src_parts, list):
            body = "".join(str(x) for x in src_parts)
        elif isinstance(src_parts, str):
            body = src_parts
        else:
            body = ""
        body = body.strip()
        if not body:
            continue
        meta = cell.get("metadata") or {}
        meta_lbl = ""
        if isinstance(meta, dict):
            meta_lbl = str(meta.get("title") or meta.get("id") or "")[:120]
        sym = f"{i}:{ctype}"
        if meta_lbl:
            sym = f"{sym}:{meta_lbl}"
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                "jupyter",
                "ipynb_cell",
                sym,
                body + "\n",
                i + 1,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out


def chunks_ini(rel_path: str, source: str, *, max_chars: int, overlap: int) -> list[StructuredChunk]:
    from configparser import ConfigParser
    from io import StringIO

    if not source.strip():
        return []
    raw = source
    if raw.lstrip().startswith("\ufeff"):
        raw = raw.lstrip("\ufeff")
    cp = ConfigParser(interpolation=None, strict=False)
    try:
        cp.read_file(StringIO(raw))
    except Exception as exc:
        log.info("ini parse fallback for %s: %s", rel_path, exc)
        return []
    sections = cp.sections()
    if not sections and not cp.defaults():
        hdr = _build_header(rel_path, language="ini", chunk_kind="ini_file", symbol="")
        doc = hdr + "\n" + raw.strip() + "\n"
        return [
            StructuredChunk(
                document=doc,
                start_line=1,
                end_line=max(1, raw.count("\n") + 1),
                language="ini",
                chunk_kind="ini_file",
                symbol="",
            )
        ]
    out: list[StructuredChunk] = []
    lines = raw.splitlines(keepends=True)

    def section_start_line(name: str) -> int:
        target = f"[{name}]"
        for idx, ln in enumerate(lines):
            if ln.strip() == target.strip():
                return idx + 1
        return 1

    if cp.defaults():
        buf = StringIO()
        for k, v in cp.defaults().items():
            buf.write(f"{k} = {v}\n")
        body = buf.getvalue().strip()
        if body:
            hdr_kw = {}
            out.extend(
                _split_oversized(
                    rel_path,
                    "ini",
                    "ini_defaults",
                    "DEFAULT",
                    body + "\n",
                    1,
                    max_chars=max_chars,
                    overlap=overlap,
                    header_kwargs=hdr_kw,
                )
            )
    for sec in sections:
        items = "\n".join(f"{k} = {v}" for k, v in cp.items(sec)) + "\n"
        sl = section_start_line(sec)
        hdr_kw = {}
        out.extend(
            _split_oversized(
                rel_path,
                "ini",
                "ini_section",
                sec[:200],
                items.strip() + "\n",
                sl,
                max_chars=max_chars,
                overlap=overlap,
                header_kwargs=hdr_kw,
            )
        )
    return out
