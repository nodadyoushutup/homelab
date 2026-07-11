# Python (homelab overlay)

PEP 8 baseline, readability, module sizing, and change discipline for Python are
in the framework **Generic Code Agent** system prompt (**Language and format
conventions — Python**).

## Stricter convention in this repo

For **new or materially changed** Python in this repository, coverage is
**end-to-end** unless a file is clearly legacy-exempt: **every class** and **every**
`def` (public, private helpers, nested functions, methods, `__init__`, property
accessors, static/class methods) should have **full type annotations** and a
**Google-style docstring**. The **only** routine exception is **`lambda`**: use it
only for tiny inline expressions; if it needs explanation or non-obvious typing,
use a named `def` instead.

- **Functions and methods:** Annotate every parameter and the return type
  (`-> None` when there is no return). Use `typing` / built-in generics consistent
  with the file and Python version for that package.
- **Classes:** Add a Google-style class docstring (`Attributes` / `Examples` when
  useful). Annotate attributes on the class body when they are part of the
  object’s contract (follow `dataclass`, Pydantic, or local patterns when the class
  uses those).
- **Docstring depth:** Obvious private helpers may use a **one-line summary**
  only; add `Args:`, `Returns:`, `Raises:`, and other sections when they carry
  information a reader would miss. The summary line and Google layout rules still
  apply. See the [Google Python Style Guide — Docstrings](https://google.github.io/styleguide/pyguide.html#38-comments-and-docstrings).
- **Modules:** A top-of-file **module docstring is not required**; class and
  function docstrings are the required surface.

## This repository

- Primary Python trees include **`applications/langgraph/`** (agent runtime and
  framework), **`applications/rag-engine/`**, other **`applications/*`** Python
  services, and **`scripts/`**. Match imports, typing, and layout of the nearest
  package when editing.
- LangGraph secrets and env: see **`03-implementation-work.md`** (`.config/docker/langgraph.env` and related split files).
