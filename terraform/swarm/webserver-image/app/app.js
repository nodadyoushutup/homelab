(function () {
  const listingBody = document.getElementById("listing");
  const statusEl = document.getElementById("status");
  const backButton = document.getElementById("back-button");
  const addButton = document.getElementById("add-button");
  const refreshButton = document.getElementById("refresh-button");
  const uploadModal = document.getElementById("upload-modal");
  const uploadCloseButton = document.getElementById("upload-close");
  const uploadCancelButton = document.getElementById("upload-cancel");
  const uploadSubmitButton = document.getElementById("upload-submit");
  const uploadInput = document.getElementById("upload-input");
  const uploadDropzone = document.getElementById("upload-dropzone");
  const uploadSelection = document.getElementById("upload-selection");
  const uploadStatus = document.getElementById("upload-status");
  const sortHeaders = Array.from(document.querySelectorAll(".sort-header"));
  const naturalCollator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });

  let selectedFiles = [];
  let uploading = false;
  let currentEntries = [];
  let sortState = {
    key: "name",
    direction: "asc",
  };

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

  addButton.addEventListener("click", () => {
    openUploadModal();
  });

  uploadCloseButton.addEventListener("click", closeUploadModal);
  uploadCancelButton.addEventListener("click", closeUploadModal);
  uploadSubmitButton.addEventListener("click", uploadSelectedFiles);

  uploadInput.addEventListener("change", (event) => {
    const files = Array.from(event.target.files || []);
    setSelectedFiles(files);
  });

  uploadDropzone.addEventListener("dragover", (event) => {
    event.preventDefault();
    uploadDropzone.classList.add("border-amber-400", "bg-amber-500/5");
  });

  uploadDropzone.addEventListener("dragleave", () => {
    uploadDropzone.classList.remove("border-amber-400", "bg-amber-500/5");
  });

  uploadDropzone.addEventListener("drop", (event) => {
    event.preventDefault();
    uploadDropzone.classList.remove("border-amber-400", "bg-amber-500/5");
    const files = Array.from(event.dataTransfer?.files || []);
    setSelectedFiles(files);
  });

  uploadModal.addEventListener("click", (event) => {
    if (event.target === uploadModal) {
      closeUploadModal();
    }
  });

  for (const button of sortHeaders) {
    button.addEventListener("click", () => {
      const sortKey = button.dataset.sortKey;
      if (!sortKey) {
        return;
      }

      if (sortState.key === sortKey) {
        sortState.direction = sortState.direction === "asc" ? "desc" : "asc";
      } else {
        sortState = { key: sortKey, direction: "asc" };
      }

      updateSortIndicators();
      renderRows(currentPath, currentEntries);
    });
  }

  listingBody.addEventListener("click", async (event) => {
    const deleteButton = event.target.closest(".delete-entry");
    if (!deleteButton) {
      return;
    }

    const targetPath = deleteButton.dataset.targetPath;
    const targetName = deleteButton.dataset.targetName || targetPath;
    if (!targetPath) {
      return;
    }

    const confirmed = window.confirm(`Delete "${targetName}"? This cannot be undone.`);
    if (!confirmed) {
      return;
    }

    deleteButton.disabled = true;
    statusEl.textContent = `Deleting ${targetName}...`;

    try {
      const response = await fetch(targetPath, { method: "DELETE" });
      if (!response.ok) {
        throw new Error(`Delete failed with ${response.status}`);
      }

      statusEl.textContent = `Deleted ${targetName}`;
      await loadDirectory(currentPath);
    } catch (error) {
      statusEl.textContent = `Delete failed for ${targetName}: ${error.message}`;
      deleteButton.disabled = false;
    }
  });

  updateSortIndicators();
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
      currentEntries = rows;
      renderRows(path, currentEntries);
      statusEl.textContent = `${rows.length} item(s)`;
    } catch (error) {
      currentEntries = [];
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
      .map((entry) => enrichEntry(path, entry))
      .sort(compareEntries);

    if (visibleRows.length === 0) {
      listingBody.innerHTML = '<tr><td class="px-4 py-4 text-slate-400" colspan="5">This directory is empty.</td></tr>';
      return;
    }

    listingBody.innerHTML = visibleRows
      .map((entry) => renderRow(entry))
      .join("");
  }

  function enrichEntry(path, entry) {
    const rawName = String(entry.name);
    const cleanedName = rawName.replace(/\/+$/, "");
    const nextPath = path ? `${path}/${cleanedName}` : cleanedName;
    const isDirectory = entry.type === "directory";

    const href = isDirectory
      ? `/?path=${encodeURIComponent(nextPath)}`
      : "/" + encodePath(nextPath);
    const deletePath = "/" + encodePath(nextPath) + (isDirectory ? "/" : "");

    const logicalSize = numberOrNull(entry.size);
    const allocatedSize = numberOrNull(entry.allocated_size);
    const effectiveSize = isDirectory ? null : (allocatedSize ?? logicalSize);

    return {
      cleanedName,
      deletePath,
      href,
      isDirectory,
      logicalSize,
      allocatedSize,
      effectiveSize,
      modifiedDisplay: entry.mtime ? formatDate(entry.mtime) : "-",
      modifiedEpoch: dateEpochOrNull(entry.mtime),
      typeLabel: isDirectory ? "Directory" : "File",
    };
  }

  function compareEntries(left, right) {
    if (sortState.key === "name") {
      return compareString(left.cleanedName, right.cleanedName, sortState.direction);
    }

    if (sortState.key === "type") {
      const byType = compareString(left.typeLabel, right.typeLabel, sortState.direction);
      if (byType !== 0) {
        return byType;
      }
      return compareString(left.cleanedName, right.cleanedName, "asc");
    }

    if (sortState.key === "size") {
      const bySize = compareNullableNumbers(left.effectiveSize, right.effectiveSize, sortState.direction);
      if (bySize !== 0) {
        return bySize;
      }
      return compareString(left.cleanedName, right.cleanedName, "asc");
    }

    if (sortState.key === "modified") {
      const byModified = compareNullableNumbers(left.modifiedEpoch, right.modifiedEpoch, sortState.direction);
      if (byModified !== 0) {
        return byModified;
      }
      return compareString(left.cleanedName, right.cleanedName, "asc");
    }

    return compareString(left.cleanedName, right.cleanedName, "asc");
  }

  function compareString(left, right, direction) {
    const compared = naturalCollator.compare(String(left || ""), String(right || ""));
    return direction === "desc" ? -compared : compared;
  }

  function compareNullableNumbers(left, right, direction) {
    const leftMissing = !Number.isFinite(left);
    const rightMissing = !Number.isFinite(right);

    if (leftMissing && rightMissing) {
      return 0;
    }
    if (leftMissing) {
      return 1;
    }
    if (rightMissing) {
      return -1;
    }

    if (left === right) {
      return 0;
    }

    return direction === "desc" ? right - left : left - right;
  }

  function updateSortIndicators() {
    for (const button of sortHeaders) {
      const key = button.dataset.sortKey;
      if (!key) {
        continue;
      }

      const indicator = document.querySelector(`[data-sort-indicator-for="${key}"]`);
      const header = button.closest("th");

      if (key === sortState.key) {
        if (indicator) {
          indicator.textContent = sortState.direction === "asc" ? "^" : "v";
          indicator.classList.remove("text-slate-500");
          indicator.classList.add("text-amber-300");
        }
        if (header) {
          header.setAttribute("aria-sort", sortState.direction === "asc" ? "ascending" : "descending");
        }
        button.classList.add("text-amber-300");
      } else {
        if (indicator) {
          indicator.textContent = "-";
          indicator.classList.remove("text-amber-300");
          indicator.classList.add("text-slate-500");
        }
        if (header) {
          header.setAttribute("aria-sort", "none");
        }
        button.classList.remove("text-amber-300");
      }
    }
  }

  function renderRow(entry) {
    const size = entry.isDirectory ? "-" : formatSize(entry.effectiveSize ?? 0);
    const sizeTitle = entry.isDirectory
      ? "Directory"
      : getSizeTooltip(entry.allocatedSize, entry.logicalSize, entry.effectiveSize);

    return `<tr class="transition hover:bg-slate-800/60">
      <td class="px-4 py-3"><a class="text-amber-300 hover:text-amber-200 hover:underline" href="${escapeHtml(entry.href)}">${escapeHtml(entry.cleanedName)}</a></td>
      <td class="px-4 py-3 text-slate-300">${entry.typeLabel}</td>
      <td class="px-4 py-3 text-slate-300" title="${escapeHtml(sizeTitle)}">${escapeHtml(size)}</td>
      <td class="px-4 py-3 text-slate-400">${escapeHtml(entry.modifiedDisplay)}</td>
      <td class="px-4 py-3 text-right">
        <button
          type="button"
          class="delete-entry inline-flex items-center rounded-lg border border-rose-700/60 bg-rose-900/30 px-2.5 py-1.5 text-xs text-rose-200 transition hover:border-rose-500 hover:text-rose-100 disabled:cursor-not-allowed disabled:opacity-50"
          data-target-path="${escapeHtml(entry.deletePath)}"
          data-target-name="${escapeHtml(entry.cleanedName)}"
          title="Delete"
          aria-label="Delete ${escapeHtml(entry.cleanedName)}"
        >
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>
    </tr>`;
  }

  function getSizeTooltip(allocatedSize, logicalSize, effectiveSize) {
    if (Number.isFinite(allocatedSize) && Number.isFinite(logicalSize) && allocatedSize !== logicalSize) {
      return `On disk: ${formatSize(allocatedSize)} (${allocatedSize} B) | Logical: ${formatSize(logicalSize)} (${logicalSize} B)`;
    }

    const size = Number.isFinite(effectiveSize) ? effectiveSize : logicalSize;
    if (!Number.isFinite(size)) {
      return "-";
    }

    return `${formatSize(size)} (${size} B)`;
  }

  function dateEpochOrNull(value) {
    const parsed = new Date(value);
    const timestamp = parsed.getTime();
    return Number.isFinite(timestamp) ? timestamp : null;
  }

  function numberOrNull(value) {
    const number = Number(value);
    if (!Number.isFinite(number) || number < 0) {
      return null;
    }
    return number;
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

  function openUploadModal() {
    if (uploading) {
      return;
    }

    selectedFiles = [];
    uploadInput.value = "";
    updateUploadSelection();
    uploadStatus.textContent = "";
    uploadModal.classList.remove("hidden");
    uploadModal.classList.add("flex");
  }

  function closeUploadModal(forceClose = false) {
    if (uploading && !forceClose) {
      return;
    }

    uploadModal.classList.add("hidden");
    uploadModal.classList.remove("flex");
  }

  function setSelectedFiles(files) {
    selectedFiles = files.filter((file) => file && file.name);
    updateUploadSelection();
  }

  function updateUploadSelection() {
    if (selectedFiles.length === 0) {
      uploadSelection.textContent = "No files selected.";
      uploadSubmitButton.disabled = true;
      return;
    }

    const names = selectedFiles.slice(0, 3).map((file) => file.name);
    const remaining = selectedFiles.length - names.length;
    const suffix = remaining > 0 ? ` and ${remaining} more` : "";
    uploadSelection.textContent = `${selectedFiles.length} file(s): ${names.join(", ")}${suffix}`;
    uploadSubmitButton.disabled = false;
  }

  async function uploadSelectedFiles() {
    if (uploading || selectedFiles.length === 0) {
      return;
    }

    uploading = true;
    uploadSubmitButton.disabled = true;
    uploadCancelButton.disabled = true;
    uploadCloseButton.disabled = true;

    try {
      let uploadedCount = 0;

      for (const file of selectedFiles) {
        const safeName = sanitizeFileName(file.name);
        const targetPath = currentPath
          ? `/${encodePath(currentPath)}/${encodeURIComponent(safeName)}`
          : `/${encodeURIComponent(safeName)}`;

        uploadStatus.textContent = `Uploading ${safeName}...`;
        const response = await fetch(targetPath, {
          method: "PUT",
          body: file,
          headers: {
            "Content-Type": "application/octet-stream",
          },
        });

        if (!response.ok) {
          throw new Error(`${safeName} failed with ${response.status}`);
        }

        uploadedCount += 1;
      }

      uploadStatus.textContent = `Uploaded ${uploadedCount} file(s).`;
      statusEl.textContent = `Uploaded ${uploadedCount} file(s)`;
      selectedFiles = [];
      uploadInput.value = "";
      closeUploadModal(true);
      await loadDirectory(currentPath);
    } catch (error) {
      uploadStatus.textContent = `Upload failed: ${error.message}`;
      statusEl.textContent = `Upload failed: ${error.message}`;
    } finally {
      uploading = false;
      uploadCancelButton.disabled = false;
      uploadCloseButton.disabled = false;
      updateUploadSelection();
    }
  }

  function sanitizeFileName(name) {
    return String(name).replaceAll("/", "_").replaceAll("\\", "_").trim() || "upload.bin";
  }
})();
