(function () {
  const listingBody = document.getElementById("listing");
  const statusEl = document.getElementById("status");
  const backButton = document.getElementById("back-button");
  const refreshButton = document.getElementById("refresh-button");

  const params = new URLSearchParams(window.location.search);
  const currentPath = normalizePath(params.get("path") || "");

  backButton.addEventListener("click", () => {
    if (window.history.length > 1) {
      window.history.back();
      return;
    }

    const parentPath = getParentPath(currentPath);
    window.location.href = parentPath ? `/?path=${encodeURIComponent(parentPath)}` : "/";
  });

  refreshButton.addEventListener("click", () => {
    loadDirectory(currentPath);
  });

  loadDirectory(currentPath);

  function normalizePath(value) {
    return value
      .split("/")
      .map((segment) => segment.trim())
      .filter((segment) => segment && segment !== "." && segment !== "..")
      .join("/");
  }

  function getParentPath(path) {
    const segments = path.split("/");
    segments.pop();
    return segments.join("/");
  }

  async function loadDirectory(path) {
    const apiUrl = "/api/files/" + encodePath(path) + (path ? "/" : "");
    statusEl.textContent = `Loading ${apiUrl}`;

    try {
      const response = await fetch(apiUrl, { headers: { Accept: "application/json" } });
      if (!response.ok) {
        throw new Error(`Request failed with ${response.status}`);
      }

      const payload = await response.json();
      const rows = Array.isArray(payload) ? payload : [];
      renderRows(path, rows);
      statusEl.textContent = `${rows.length} item(s)`;
    } catch (error) {
      listingBody.innerHTML = "";
      statusEl.textContent = `Failed to load directory: ${error.message}`;
    }
  }

  function encodePath(path) {
    if (!path) {
      return "";
    }

    return path
      .split("/")
      .filter(Boolean)
      .map((segment) => encodeURIComponent(segment))
      .join("/");
  }

  function renderRows(path, rows) {
    const visibleRows = rows
      .filter((entry) => entry && entry.name && entry.name !== "." && entry.name !== "..")
      .sort((left, right) => {
        const leftType = left.type === "directory" ? 0 : 1;
        const rightType = right.type === "directory" ? 0 : 1;
        if (leftType !== rightType) {
          return leftType - rightType;
        }
        return String(left.name).localeCompare(String(right.name));
      });

    if (visibleRows.length === 0) {
      listingBody.innerHTML = '<tr><td class="px-4 py-4 text-slate-400" colspan="4">This directory is empty.</td></tr>';
      return;
    }

    listingBody.innerHTML = visibleRows
      .map((entry) => renderRow(path, entry))
      .join("");
  }

  function renderRow(path, entry) {
    const name = String(entry.name);
    const cleanedName = name.replace(/\/+$/, "");
    const nextPath = path ? `${path}/${cleanedName}` : cleanedName;
    const isDirectory = entry.type === "directory";

    const href = isDirectory
      ? `/?path=${encodeURIComponent(nextPath)}`
      : "/" + encodePath(nextPath);

    const modified = entry.mtime ? formatDate(entry.mtime) : "-";
    const size = isDirectory ? "-" : formatSize(Number(entry.size) || 0);

    return `<tr class="transition hover:bg-slate-800/60">
      <td class="px-4 py-3"><a class="text-amber-300 hover:text-amber-200 hover:underline" href="${escapeHtml(href)}">${escapeHtml(cleanedName)}</a></td>
      <td class="px-4 py-3 text-slate-300">${isDirectory ? "Directory" : "File"}</td>
      <td class="px-4 py-3 text-slate-300">${escapeHtml(size)}</td>
      <td class="px-4 py-3 text-slate-400">${escapeHtml(modified)}</td>
    </tr>`;
  }

  function formatDate(value) {
    const parsed = new Date(value);
    if (Number.isNaN(parsed.getTime())) {
      return value;
    }

    return parsed.toLocaleString();
  }

  function formatSize(bytes) {
    if (!Number.isFinite(bytes) || bytes < 0) {
      return "-";
    }

    if (bytes < 1024) {
      return `${bytes} B`;
    }

    const units = ["KB", "MB", "GB", "TB"];
    let size = bytes / 1024;
    let unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }

    return `${size.toFixed(1)} ${units[unitIndex]}`;
  }

  function escapeHtml(value) {
    return String(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#39;");
  }
})();
