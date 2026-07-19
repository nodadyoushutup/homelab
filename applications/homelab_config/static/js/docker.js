"use strict";

const socket = io();

const els = {
  derivedRows: document.getElementById("derived-rows"),
  derivedEmpty: document.getElementById("derived-empty"),

  extraRows: document.getElementById("extra-rows"),
  extraEmpty: document.getElementById("extra-empty"),

  regForm: document.getElementById("reg-form"),
  regOrig: document.getElementById("r-id"),
  rAddress: document.getElementById("r-address"),
  rUsername: document.getElementById("r-username"),
  rPassword: document.getElementById("r-password"),
  regFormTitle: document.getElementById("reg-form-title"),
  regSaveBtn: document.getElementById("reg-save-btn"),
  regCancel: document.getElementById("reg-cancel-edit"),
  regRows: document.getElementById("reg-rows"),
  regEmpty: document.getElementById("reg-empty"),

  tfvars: document.getElementById("tfvars-preview"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

let currentRegistries = [];

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

// -- rendering ----------------------------------------------------------------

function sshOptsHtml(opts) {
  if (!opts || !opts.length) return '<span class="text-xs text-slate-600">&mdash;</span>';
  return `<span class="font-mono text-xs text-slate-500">${escapeHtml(
    opts.join(" ")
  )}</span>`;
}

function renderDerived(nodes) {
  els.derivedRows.innerHTML = "";
  if (!nodes.length) {
    els.derivedEmpty.hidden = false;
    return;
  }
  els.derivedEmpty.hidden = true;
  nodes.forEach((node) => {
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(node.name)}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(node.role || "")}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(node.host)}</td>
      <td class="px-4 py-3 max-w-md truncate" title="${escapeHtml(
        (node.ssh_opts || []).join(" ")
      )}">${sshOptsHtml(node.ssh_opts)}</td>`;
    els.derivedRows.appendChild(row);
  });
}

function renderExtra(hosts) {
  els.extraRows.innerHTML = "";
  if (!hosts.length) {
    els.extraEmpty.hidden = false;
    return;
  }
  els.extraEmpty.hidden = true;
  hosts.forEach((host) => {
    const providerHost = host.provider_host || host.host;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(host.name)}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(providerHost)}</td>
      <td class="px-4 py-3 max-w-md truncate" title="${escapeHtml(
        (host.ssh_opts || []).join(" ")
      )}">${sshOptsHtml(host.ssh_opts)}</td>`;
    els.extraRows.appendChild(row);
  });
}

function renderRegistries(auths) {
  currentRegistries = auths;
  els.regRows.innerHTML = "";
  if (!auths.length) {
    els.regEmpty.hidden = false;
    return;
  }
  els.regEmpty.hidden = true;
  auths.forEach((auth) => {
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-mono text-xs text-slate-300">${escapeHtml(auth.address)}</td>
      <td class="px-4 py-3 text-xs text-slate-400">${escapeHtml(auth.username) || '<span class="text-slate-600">&mdash;</span>'}</td>
      <td class="px-4 py-3 text-xs text-slate-500">${auth.password ? "••••••••" : '<span class="text-slate-600">&mdash;</span>'}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit-reg="${escapeHtml(auth.address)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete-reg="${escapeHtml(auth.address)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.regRows.appendChild(row);
  });
}

function renderSnapshot(snap) {
  if (!snap) return;
  if (snap.derived) renderDerived(snap.derived);
  if (snap.extra_hosts) renderExtra(snap.extra_hosts);
  if (snap.registry_auths) renderRegistries(snap.registry_auths);
}

function renderStatus(status) {
  if (!status) return;
  els.driftBanner.style.display = status.external_change ? "flex" : "none";
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api("/api/docker/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

// -- registry form ------------------------------------------------------------

function regEditing() {
  return Boolean(els.regOrig.value);
}

function resetRegForm() {
  els.regOrig.value = "";
  els.regForm.reset();
  els.regFormTitle.innerHTML = '<i class="fa-solid fa-box-archive"></i> Add registry auth';
  els.regSaveBtn.hidden = false;
  els.regSaveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add registry';
  els.regCancel.hidden = true;
}

function startRegEdit(auth) {
  els.regOrig.value = auth.address;
  els.rAddress.value = auth.address;
  els.rUsername.value = auth.username;
  els.rPassword.value = auth.password;
  els.regFormTitle.innerHTML = `<i class="fa-solid fa-box-archive"></i> Edit ${escapeHtml(
    auth.address
  )}`;
  els.regSaveBtn.hidden = true;
  els.regCancel.hidden = false;
  els.regCancel.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.rAddress.focus();
}

function buildRegPayload() {
  return {
    address: els.rAddress.value.trim(),
    username: els.rUsername.value.trim(),
    password: els.rPassword.value,
  };
}

async function autosaveReg() {
  const orig = els.regOrig.value;
  if (!orig) return;
  const payload = buildRegPayload();
  if (!payload.address) {
    setSaveState("error", "Address is required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/docker/registry/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    els.regOrig.value = updated.address;
    els.regFormTitle.innerHTML = `<i class="fa-solid fa-box-archive"></i> Edit ${escapeHtml(
      updated.address
    )}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveRegDebounced = debounce(autosaveReg, 450);

els.regForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (regEditing()) {
    autosaveReg();
    return;
  }
  const payload = buildRegPayload();
  try {
    await api("/api/docker/registry", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.address}`, "success");
    resetRegForm();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.regCancel.addEventListener("click", resetRegForm);
[els.rAddress, els.rUsername, els.rPassword].forEach((el) =>
  el.addEventListener("input", () => {
    if (regEditing()) autosaveRegDebounced();
  })
);

els.regRows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit-reg]");
  if (editBtn) {
    const auth = currentRegistries.find((a) => a.address === editBtn.dataset.editReg);
    if (auth) startRegEdit(auth);
    return;
  }
  const delBtn = event.target.closest("[data-delete-reg]");
  if (delBtn) {
    if (!confirm(`Delete registry auth "${delBtn.dataset.deleteReg}"?`)) return;
    try {
      await api(`/api/docker/registry/${encodeURIComponent(delBtn.dataset.deleteReg)}`, {
        method: "DELETE",
      });
      toast(`Deleted ${delBtn.dataset.deleteReg}`, "success");
      refreshTfvars();
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

// -- reload / preview ---------------------------------------------------------

async function doReload() {
  try {
    const data = await api("/api/docker/reload", { method: "POST" });
    renderSnapshot(data);
    renderStatus(data.status);
    resetRegForm();
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
    toast("Copied docker.tfvars to clipboard", "success");
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

socket.on("docker:providers", (snap) => {
  renderSnapshot(snap);
  refreshTfvars();
});
socket.on("docker:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api("/api/docker/providers");
    renderSnapshot(data);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
