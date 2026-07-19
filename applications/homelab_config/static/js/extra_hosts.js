"use strict";

const socket = io();

const els = {
  hostForm: document.getElementById("host-form"),
  hostOrig: document.getElementById("h-id"),
  hName: document.getElementById("h-name"),
  hHost: document.getElementById("h-host"),
  hUser: document.getElementById("h-user"),
  hPort: document.getElementById("h-port"),
  hKey: document.getElementById("h-ssh-key"),
  hKeyHint: document.getElementById("h-ssh-key-hint"),
  hPassword: document.getElementById("h-ssh-password"),
  hSync: document.getElementById("h-sync-ssh"),
  hostFormTitle: document.getElementById("host-form-title"),
  hostSaveBtn: document.getElementById("host-save-btn"),
  hostCancel: document.getElementById("host-cancel-edit"),
  hostRows: document.getElementById("host-rows"),
  hostEmpty: document.getElementById("host-empty"),

  applyModal: document.getElementById("modal-apply"),
  applyHostName: document.getElementById("apply-host-name"),
  applyPhase: document.getElementById("apply-phase"),
  applyLog: document.getElementById("apply-log"),
  applyRun: document.getElementById("apply-run"),

  reloadBtn: document.getElementById("reload-btn"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

let currentHosts = [];
let keySets = [];

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

function populateKeyOptions(selected) {
  const hasSets = keySets.length > 0;
  let chosen = selected != null ? selected : els.hKey.value;
  if (chosen == null) chosen = "";
  const opts = ['<option value="">&mdash; none (password) &mdash;</option>'];
  keySets.forEach((name) => {
    opts.push(`<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`);
  });
  if (chosen && !keySets.includes(chosen)) {
    opts.push(
      `<option value="${escapeHtml(chosen)}">${escapeHtml(chosen)} (missing)</option>`
    );
  }
  els.hKey.innerHTML = opts.join("");
  els.hKey.value = chosen;
  els.hKey.disabled = !hasSets;
  if (els.hKeyHint) {
    els.hKeyHint.innerHTML = hasSets
      ? 'Key set from <a href="/ssh" class="text-sky-400 hover:underline">SSH &rsaquo; SSH Key Sets</a>'
      : 'No key sets yet — add one under <a href="/ssh" class="text-sky-400 hover:underline">SSH &rsaquo; SSH Key Sets</a>, or use a password.';
  }
}

async function loadKeySets(selected) {
  try {
    const data = await api("/api/ssh/sets");
    keySets = (data.sets || []).map((s) => s.name);
  } catch (err) {
    keySets = [];
  }
  populateKeyOptions(selected != null ? selected : "");
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

function hostKeyCell(host) {
  if (host.ssh_key) {
    return `<span class="inline-flex items-center gap-1.5 rounded-full border border-slate-600/50 bg-slate-700/40 px-2.5 py-0.5 text-xs font-medium text-slate-300"><i class="fa-solid fa-key text-[10px]"></i>${escapeHtml(
      host.ssh_key
    )}</span>`;
  }
  if (host.ssh_password) {
    return '<span class="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-0.5 text-xs font-medium text-amber-300"><i class="fa-solid fa-lock text-[10px]"></i>password</span>';
  }
  return '<span class="text-xs text-slate-600">&mdash;</span>';
}

function hostSyncBadge(host) {
  if (!host.sync_ssh) return "";
  return '<span class="ml-1.5 inline-flex items-center gap-1 rounded-full border border-sky-500/40 bg-sky-500/15 px-2 py-0.5 align-middle text-[10px] font-medium text-sky-300" title="Sync SSH on: Apply pushes this key set + authorized_keys"><i class="fa-solid fa-arrows-rotate"></i>sync</span>';
}

function renderHosts(hosts) {
  currentHosts = hosts;
  els.hostRows.innerHTML = "";
  if (!hosts.length) {
    els.hostEmpty.hidden = false;
    return;
  }
  els.hostEmpty.hidden = true;
  hosts.forEach((host) => {
    const target = `${host.ssh_user}@${host.host}:${host.ssh_port}`;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(host.name)}${hostSyncBadge(host)}</div>
        <div class="font-mono text-xs text-slate-500">${escapeHtml(host.host)}</div>
      </td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(target)}</td>
      <td class="px-4 py-3">${hostKeyCell(host)}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-apply-host="${escapeHtml(host.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-emerald-300" title="Apply: push/sync SSH to this host">
          <i class="fa-solid fa-wand-magic-sparkles"></i>
        </button>
        <button data-edit-host="${escapeHtml(host.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete-host="${escapeHtml(host.name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.hostRows.appendChild(row);
  });
}

function renderSnapshot(snap) {
  if (!snap) return;
  if (snap.extra_hosts) renderHosts(snap.extra_hosts);
}

function renderStatus(status) {
  if (!status) return;
  els.driftBanner.style.display = status.external_change ? "flex" : "none";
}

// -- extra host form ----------------------------------------------------------

function hostEditing() {
  return Boolean(els.hostOrig.value);
}

function resetHostForm() {
  els.hostOrig.value = "";
  els.hostForm.reset();
  els.hPort.value = "22";
  populateKeyOptions("");
  els.hostFormTitle.innerHTML = '<i class="fa-solid fa-server"></i> Add extra host';
  els.hostSaveBtn.hidden = false;
  els.hostSaveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add host';
  els.hostCancel.hidden = true;
}

function startHostEdit(host) {
  els.hostOrig.value = host.name;
  els.hName.value = host.name;
  els.hHost.value = host.host;
  els.hUser.value = host.ssh_user;
  els.hPort.value = host.ssh_port;
  populateKeyOptions(host.ssh_key || "");
  els.hPassword.value = host.ssh_password || "";
  els.hSync.checked = Boolean(host.sync_ssh);
  els.hostFormTitle.innerHTML = `<i class="fa-solid fa-server"></i> Edit ${escapeHtml(
    host.name
  )}`;
  els.hostSaveBtn.hidden = true;
  els.hostCancel.hidden = false;
  els.hostCancel.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  els.hName.focus();
}

function buildHostPayload() {
  return {
    name: els.hName.value.trim(),
    host: els.hHost.value.trim(),
    ssh_user: els.hUser.value.trim(),
    ssh_port: Number(els.hPort.value) || 22,
    ssh_key: els.hKey.value.trim(),
    ssh_password: els.hPassword.value,
    sync_ssh: els.hSync.checked,
  };
}

async function autosaveHost() {
  const orig = els.hostOrig.value;
  if (!orig) return;
  const payload = buildHostPayload();
  if (!payload.name || !payload.host || !payload.ssh_user) {
    setSaveState("error", "Name, host and user are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/extra-hosts/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    els.hostOrig.value = updated.name;
    els.hostFormTitle.innerHTML = `<i class="fa-solid fa-server"></i> Edit ${escapeHtml(
      updated.name
    )}`;
    setSaveState("saved");
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveHostDebounced = debounce(autosaveHost, 450);

els.hostForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (hostEditing()) {
    autosaveHost();
    return;
  }
  const payload = buildHostPayload();
  try {
    await api("/api/extra-hosts", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.name}`, "success");
    resetHostForm();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.hostCancel.addEventListener("click", resetHostForm);
[els.hName, els.hHost, els.hUser, els.hPort, els.hPassword].forEach((el) =>
  el.addEventListener("input", () => {
    if (hostEditing()) autosaveHostDebounced();
  })
);
[els.hKey, els.hSync].forEach((el) =>
  el.addEventListener("change", () => {
    if (hostEditing()) autosaveHost();
  })
);

els.hostRows.addEventListener("click", async (event) => {
  const applyBtn = event.target.closest("[data-apply-host]");
  if (applyBtn) {
    openApplyModal(applyBtn.dataset.applyHost);
    return;
  }
  const editBtn = event.target.closest("[data-edit-host]");
  if (editBtn) {
    const host = currentHosts.find((h) => h.name === editBtn.dataset.editHost);
    if (host) startHostEdit(host);
    return;
  }
  const delBtn = event.target.closest("[data-delete-host]");
  if (delBtn) {
    if (!confirm(`Delete extra host "${delBtn.dataset.deleteHost}"?`)) return;
    try {
      await api(`/api/extra-hosts/${encodeURIComponent(delBtn.dataset.deleteHost)}`, {
        method: "DELETE",
      });
      toast(`Deleted ${delBtn.dataset.deleteHost}`, "success");
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

// -- reload -------------------------------------------------------------------

async function doReload() {
  try {
    const data = await api("/api/extra-hosts/reload", { method: "POST" });
    renderSnapshot(data);
    renderStatus(data.status);
    resetHostForm();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

els.reloadBtn.addEventListener("click", doReload);
els.driftReload.addEventListener("click", doReload);

// -- extra-host SSH apply -----------------------------------------------------

let applyHost = null;
let applyBusy = false;

function appendApplyLog(level, message) {
  const colors = {
    step: "text-sky-300",
    cmd: "text-slate-500",
    ok: "text-emerald-300",
    warn: "text-amber-300",
    error: "text-rose-300",
    info: "text-slate-300",
  };
  const line = document.createElement("div");
  line.className = colors[level] || "text-slate-300";
  line.textContent = message;
  els.applyLog.appendChild(line);
  els.applyLog.scrollTop = els.applyLog.scrollHeight;
}

function setApplyBusy(busy) {
  applyBusy = busy;
  els.applyRun.disabled = busy;
  els.applyRun.innerHTML = busy
    ? '<i class="fa-solid fa-circle-notch fa-spin mr-1.5"></i>Pushing…'
    : '<i class="fa-solid fa-play mr-1.5"></i>Push SSH';
}

function openApplyModal(name) {
  applyHost = name;
  els.applyHostName.textContent = name;
  els.applyLog.innerHTML = "";
  els.applyPhase.textContent = "";
  setApplyBusy(false);
  els.applyModal.style.display = "flex";
}

async function startApply() {
  if (!applyHost || applyBusy) return;
  els.applyLog.innerHTML = "";
  els.applyPhase.textContent = "· pushing…";
  setApplyBusy(true);
  appendApplyLog("step", `Applying ${applyHost}…`);
  try {
    await api(`/api/extra-hosts/${encodeURIComponent(applyHost)}/apply`, {
      method: "POST",
    });
  } catch (err) {
    appendApplyLog("error", err.message);
    els.applyPhase.textContent = "";
    setApplyBusy(false);
  }
}

els.applyRun.addEventListener("click", startApply);
els.applyModal.addEventListener("click", (event) => {
  if (event.target === els.applyModal || event.target.closest("[data-close]")) {
    els.applyModal.style.display = "none";
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") els.applyModal.style.display = "none";
});

socket.on("extra_hosts:apply:log", (data) => {
  if (!data || data.host !== applyHost) return;
  appendApplyLog(data.level, data.message);
});
socket.on("extra_hosts:apply:done", (data) => {
  if (!data || data.host !== applyHost) return;
  setApplyBusy(false);
  els.applyPhase.textContent = "";
  if (data.ok) {
    toast(`Applied ${data.host}`, "success");
  } else {
    toast(`Apply failed for ${data.host} — see the log`, "error");
  }
});

socket.on("docker:providers", renderSnapshot);
socket.on("docker:status", renderStatus);
socket.on("ssh:sets", (snapshot) => {
  keySets = (snapshot.sets || []).map((s) => s.name);
  populateKeyOptions(els.hKey.value || "");
});

async function init() {
  setSaveState("idle");
  try {
    await loadKeySets();
    const data = await api("/api/extra-hosts");
    renderSnapshot(data);
    renderStatus(data.status);
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
