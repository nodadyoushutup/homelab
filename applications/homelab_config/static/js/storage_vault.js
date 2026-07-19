"use strict";

const socket = io();

const els = {
  mount: document.getElementById("f-mount"),
  rows: document.getElementById("secret-rows"),
  empty: document.getElementById("empty-state"),
  tfvars: document.getElementById("tfvars-preview"),
  form: document.getElementById("secret-form"),
  origKey: document.getElementById("f-id"),
  group: document.getElementById("f-group"),
  name: document.getElementById("f-name"),
  fieldsRows: document.getElementById("fields-rows"),
  addField: document.getElementById("add-field"),
  formTitle: document.getElementById("form-title"),
  saveBtn: document.getElementById("save-btn"),
  cancelEdit: document.getElementById("cancel-edit"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftReload: document.getElementById("drift-reload"),
};

let currentSecrets = [];

function debounce(fn, ms) {
  let timer;
  return (...args) => {
    clearTimeout(timer);
    timer = setTimeout(() => fn(...args), ms);
  };
}

let saveStateTimer;
function setSaveState(kind, message) {
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    els.saveState.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    els.saveState.className = "text-sm text-sky-300";
    els.saveState.title = "Saving…";
  } else if (kind === "saved") {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    els.saveState.className = "text-sm text-emerald-300";
    els.saveState.title = "Saved";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    els.saveState.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    els.saveState.className = "text-xs font-medium text-rose-300";
    els.saveState.title = message || "Save failed";
  } else {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    els.saveState.className = "text-sm text-slate-500";
    els.saveState.title = "Auto-save on";
  }
}

function isEditing() {
  return Boolean(els.origKey.value);
}

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new Error(data.error || `Request failed (${response.status})`);
  }
  return data;
}

function toast(message, kind = "info") {
  const palette = {
    info: "bg-slate-800 text-slate-100 border-slate-700",
    success: "bg-emerald-500/15 text-emerald-200 border-emerald-500/40",
    error: "bg-rose-500/15 text-rose-200 border-rose-500/40",
  };
  const el = document.createElement("div");
  el.className = `pointer-events-auto rounded-lg border px-4 py-2 text-sm shadow-lg ${
    palette[kind] || palette.info
  }`;
  el.textContent = message;
  document.getElementById("toast-root").appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 300ms";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 300);
  }, 2600);
}

// -- fields sub-editor -------------------------------------------------------

function fieldRow(field = "", value = "") {
  const row = document.createElement("div");
  row.className = "flex items-center gap-2";
  row.innerHTML = `
    <input
      class="field-key w-1/3 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-sm text-slate-100 focus:border-sky-500 focus:outline-none"
      placeholder="username" />
    <input
      class="field-val flex-1 rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none"
      placeholder="value" />
    <button type="button" class="field-del rounded-md px-2 py-2 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Remove field">
      <i class="fa-solid fa-trash"></i>
    </button>`;
  row.querySelector(".field-key").value = field;
  row.querySelector(".field-val").value = value;
  return row;
}

function renderFields(fields) {
  els.fieldsRows.innerHTML = "";
  const entries = Object.entries(fields || {});
  if (!entries.length) {
    els.fieldsRows.appendChild(fieldRow());
    return;
  }
  entries.forEach(([field, value]) => els.fieldsRows.appendChild(fieldRow(field, value)));
}

function collectFields() {
  const fields = {};
  els.fieldsRows.querySelectorAll(".flex").forEach((row) => {
    const key = row.querySelector(".field-key").value.trim();
    const value = row.querySelector(".field-val").value;
    if (key) fields[key] = value;
  });
  return fields;
}

// -- table -------------------------------------------------------------------

function renderSecrets(secrets) {
  currentSecrets = secrets;
  els.rows.innerHTML = "";
  if (!secrets.length) {
    els.empty.hidden = false;
    return;
  }
  els.empty.hidden = true;

  secrets.forEach((secret) => {
    const fieldNames = Object.keys(secret.fields || {});
    const chips = fieldNames
      .map(
        (f) =>
          `<span class="mr-1 mb-1 inline-block rounded-full bg-slate-700/60 px-2 py-0.5 text-xs text-slate-300">${escapeHtml(
            f
          )}</span>`
      )
      .join("");
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(secret.group)}/${escapeHtml(
      secret.name
    )}</div>
      </td>
      <td class="px-4 py-3">${chips || '<span class="text-xs text-slate-600">none</span>'}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${escapeHtml(secret.key)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete="${escapeHtml(secret.key)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.rows.appendChild(row);
  });
}

function renderStatus(status) {
  if (!status) return;
  els.driftBanner.style.display = status.external_change ? "flex" : "none";
}

function renderConfig(config) {
  if (!config) return;
  if (document.activeElement !== els.mount) {
    els.mount.value = config.mount_path || "";
  }
  renderSecrets(config.secrets || []);
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api("/api/storage/vault/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function resetForm() {
  els.origKey.value = "";
  els.form.reset();
  renderFields({});
  els.formTitle.textContent = "Add secret";
  els.saveBtn.hidden = false;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add secret';
  els.cancelEdit.hidden = true;
}

function startEdit(secret) {
  els.origKey.value = secret.key;
  els.group.value = secret.group;
  els.name.value = secret.name;
  renderFields(secret.fields || {});
  els.formTitle.textContent = `Edit ${secret.key}`;
  els.saveBtn.hidden = true;
  els.cancelEdit.hidden = false;
  els.cancelEdit.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.group.focus();
}

function buildPayload() {
  return {
    group: els.group.value.trim(),
    name: els.name.value.trim(),
    fields: collectFields(),
  };
}

async function autosaveEdit() {
  const orig = els.origKey.value;
  if (!orig) return;
  const payload = buildPayload();
  if (!payload.group || !payload.name) {
    setSaveState("error", "Group and name are required");
    return;
  }
  if (!Object.keys(payload.fields).length) {
    setSaveState("error", "At least one field is required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/storage/vault/secrets/${orig}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    els.origKey.value = updated.key;
    els.formTitle.textContent = `Edit ${updated.key}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveEditDebounced = debounce(autosaveEdit, 500);

function scheduleEditAutosave() {
  if (isEditing()) autosaveEditDebounced();
}

async function saveMount() {
  try {
    setSaveState("saving");
    await api("/api/storage/vault/mount", {
      method: "PUT",
      body: JSON.stringify({ mount_path: els.mount.value.trim() }),
    });
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const saveMountDebounced = debounce(saveMount, 600);

els.mount.addEventListener("input", saveMountDebounced);
els.mount.addEventListener("blur", saveMount);

els.addField.addEventListener("click", () => {
  els.fieldsRows.appendChild(fieldRow());
});

els.fieldsRows.addEventListener("click", (event) => {
  const del = event.target.closest(".field-del");
  if (!del) return;
  del.closest(".flex").remove();
  scheduleEditAutosave();
});

els.fieldsRows.addEventListener("input", scheduleEditAutosave);

els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (isEditing()) {
    autosaveEdit();
    return;
  }
  const payload = buildPayload();
  try {
    await api("/api/storage/vault/secrets", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.group}/${payload.name}`, "success");
    resetForm();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.cancelEdit.addEventListener("click", resetForm);

[els.group, els.name].forEach((el) =>
  el.addEventListener("input", scheduleEditAutosave)
);

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const secret = currentSecrets.find((s) => s.key === editBtn.dataset.edit);
    if (secret) startEdit(secret);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete secret "${delBtn.dataset.delete}"?`)) return;
    try {
      await api(`/api/storage/vault/secrets/${delBtn.dataset.delete}`, {
        method: "DELETE",
      });
      toast(`Deleted ${delBtn.dataset.delete}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

async function doReload() {
  try {
    const data = await api("/api/storage/vault/reload", { method: "POST" });
    renderConfig(data);
    renderStatus(data.status);
    resetForm();
    refreshTfvars();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

els.reloadBtn.addEventListener("click", doReload);
els.driftReload.addEventListener("click", doReload);

els.previewBtn.addEventListener("click", async () => {
  await refreshTfvars();
  els.previewModal.style.display = "flex";
});
els.previewCopy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(els.tfvars.textContent || "");
    toast("Copied config.tfvars to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});
els.previewModal.addEventListener("click", (event) => {
  if (event.target === els.previewModal || event.target.closest("[data-close]")) {
    els.previewModal.style.display = "none";
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") els.previewModal.style.display = "none";
});

socket.on("vault_config:config", (config) => {
  renderConfig(config);
  refreshTfvars();
});
socket.on("vault_config:status", renderStatus);

async function init() {
  setSaveState("idle");
  renderFields({});
  try {
    const data = await api("/api/storage/vault/config");
    renderConfig(data);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
