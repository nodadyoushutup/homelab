"use strict";

const socket = io();

const els = {
  rows: document.getElementById("node-rows"),
  empty: document.getElementById("empty-state"),
  tfvars: document.getElementById("tfvars-preview"),
  form: document.getElementById("node-form"),
  origName: document.getElementById("f-id"),
  name: document.getElementById("f-name"),
  host: document.getElementById("f-host"),
  user: document.getElementById("f-user"),
  role: document.getElementById("f-role"),
  port: document.getElementById("f-port"),
  sshKey: document.getElementById("f-ssh-key"),
  sshKeyHint: document.getElementById("f-ssh-key-hint"),
  sshPassword: document.getElementById("f-ssh-password"),
  syncSsh: document.getElementById("f-sync-ssh"),
  labels: document.getElementById("f-labels"),
  labelByName: document.getElementById("f-label-by-name"),
  formTitle: document.getElementById("form-title"),
  saveBtn: document.getElementById("save-btn"),
  cancelEdit: document.getElementById("cancel-edit"),
  reloadBtn: document.getElementById("reload-btn"),
  previewBtn: document.getElementById("preview-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewCopy: document.getElementById("preview-copy"),
  applyBtn: document.getElementById("apply-btn"),
  applyModal: document.getElementById("modal-apply"),
  applyPhase: document.getElementById("apply-phase"),
  applyPlanWrap: document.getElementById("apply-plan-wrap"),
  applyPlan: document.getElementById("apply-plan"),
  applyDestructive: document.getElementById("apply-destructive"),
  applyDestructiveText: document.getElementById("apply-destructive-text"),
  applyConfirm: document.getElementById("apply-confirm"),
  applyLog: document.getElementById("apply-log"),
  applyReplan: document.getElementById("apply-replan"),
  applyRun: document.getElementById("apply-run"),
  saveState: document.getElementById("save-state"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

let currentNodes = [];

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
    // Quick spinner while a save is in flight.
    els.saveState.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    els.saveState.className = "text-sm text-sky-300";
    els.saveState.title = "Saving…";
  } else if (kind === "saved") {
    // Brief confirmation, then fall back to the idle cloud.
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
    // Idle: just the cloud icon (auto-save is always on).
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    els.saveState.className = "text-sm text-slate-500";
    els.saveState.title = "Auto-save on";
  }
}

function isEditing() {
  return Boolean(els.origName.value);
}

function defaultKeyValue() {
  // No default key set: a new node starts with "none" until the operator picks one.
  return "";
}

function populateKeyOptions(selected) {
  const hasSets = keySets.length > 0;
  let chosen = selected != null ? selected : els.sshKey.value;
  if (chosen == null) chosen = "";
  const opts = ['<option value="">&mdash; none (password) &mdash;</option>'];
  keySets.forEach((name) => {
    opts.push(`<option value="${escapeHtml(name)}">${escapeHtml(name)}</option>`);
  });
  // Keep a node's key visible even if that set no longer exists on disk.
  if (chosen && !keySets.includes(chosen)) {
    opts.push(
      `<option value="${escapeHtml(chosen)}">${escapeHtml(chosen)} (missing)</option>`
    );
  }
  els.sshKey.innerHTML = opts.join("");
  els.sshKey.value = chosen;
  els.sshKey.disabled = !hasSets;
  if (els.sshKeyHint) {
    els.sshKeyHint.innerHTML = hasSets
      ? 'Key set from <a href="/ssh" class="text-sky-400 hover:underline">Machines &rsaquo; SSH</a>'
      : 'No key sets yet — add one under <a href="/ssh" class="text-sky-400 hover:underline">Machines &rsaquo; SSH</a>, or use a password.';
  }
}

async function loadKeySets(selected) {
  try {
    const data = await api("/api/ssh/sets");
    keySets = (data.sets || []).map((s) => s.name);
  } catch (err) {
    keySets = [];
  }
  populateKeyOptions(selected != null ? selected : defaultKeyValue());
}

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

function labelsToString(labels) {
  return Object.entries(labels || {})
    .map(([key, value]) => `${key}=${value}`)
    .join(", ");
}

// Required fields flash a red border while empty so gaps are obvious pre-save.
// ssh_key / ssh_password / port stay optional and are never marked.
function requiredFields() {
  return [els.name, els.host, els.user, els.role, els.labels];
}
function markRequired(el) {
  if (!el) return;
  const empty = !String(el.value || "").trim();
  el.style.borderColor = empty ? "#f43f5e" : "";
}
function markAllRequired() {
  requiredFields().forEach(markRequired);
}

// "Label by name" mirrors the placement convention used in Terraform: a node
// carries `role=<name>` so services pin to it via `node.labels.role==<name>`.
function applyLabelByName() {
  if (els.labelByName.checked) {
    const name = els.name.value.trim();
    els.labels.value = name ? `role=${name}` : "";
    els.labels.disabled = true;
  } else {
    els.labels.disabled = false;
  }
  markRequired(els.labels);
}

function labelsFromForm() {
  if (els.labelByName.checked) {
    const name = els.name.value.trim();
    return name ? { role: name } : {};
  }
  return stringToLabels(els.labels.value);
}

function stringToLabels(text) {
  const labels = {};
  (text || "")
    .split(",")
    .map((part) => part.trim())
    .filter(Boolean)
    .forEach((pair) => {
      const idx = pair.indexOf("=");
      if (idx === -1) {
        labels[pair] = "true";
      } else {
        const key = pair.slice(0, idx).trim();
        const value = pair.slice(idx + 1).trim();
        if (key) labels[key] = value;
      }
    });
  return labels;
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

function keyCell(node) {
  if (node.ssh_key) {
    return `<span class="inline-flex items-center gap-1.5 rounded-full border border-slate-600/50 bg-slate-700/40 px-2.5 py-0.5 text-xs font-medium text-slate-300"><i class="fa-solid fa-key text-[10px]"></i>${escapeHtml(
      node.ssh_key
    )}</span>`;
  }
  if (node.ssh_password) {
    return `<span class="inline-flex items-center gap-1.5 rounded-full border border-amber-500/40 bg-amber-500/15 px-2.5 py-0.5 text-xs font-medium text-amber-300"><i class="fa-solid fa-lock text-[10px]"></i>password</span>`;
  }
  return `<span class="text-xs text-slate-600">&mdash;</span>`;
}

function syncBadge(node) {
  if (!node.sync_ssh) return "";
  return `<span class="ml-1.5 inline-flex items-center gap-1 rounded-full border border-sky-500/40 bg-sky-500/15 px-2 py-0.5 align-middle text-[10px] font-medium text-sky-300" title="Sync SSH on: bootstrap will push this key set + authorized_keys to the node"><i class="fa-solid fa-arrows-rotate"></i>sync</span>`;
}

function sshString(node) {
  // user[:••••]@host:port - show the password masked (like a real ssh string)
  // when one is set. The dots track the password length for familiarity, capped
  // so a long secret can't blow out the column.
  let cred = escapeHtml(node.ssh_user);
  if (node.ssh_password) {
    cred += ":" + "•".repeat(Math.min(String(node.ssh_password).length, 24));
  }
  return `${cred}@${escapeHtml(node.host)}:${escapeHtml(node.ssh_port)}`;
}

function roleBadge(role) {
  const cls =
    role === "manager"
      ? "bg-sky-500/15 text-sky-300 border-sky-500/40"
      : "bg-slate-700/40 text-slate-300 border-slate-600/50";
  const icon = role === "manager" ? "fa-crown" : "fa-server";
  return `<span class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${cls}"><i class="fa-solid ${icon}"></i>${escapeHtml(
    role
  )}</span>`;
}

function renderNodes(nodes) {
  currentNodes = nodes;
  els.rows.innerHTML = "";
  if (!nodes.length) {
    els.empty.hidden = false;
    return;
  }
  els.empty.hidden = true;

  nodes.forEach((node) => {
    const labelText = labelsToString(node.labels);
    const labelHtml = labelText
      ? `<span class="font-mono text-xs text-slate-400">${escapeHtml(labelText)}</span>`
      : `<span class="text-xs text-slate-600">&mdash;</span>`;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(node.name)}</div>
        <div class="text-xs text-slate-500">${escapeHtml(node.host)}</div>
      </td>
      <td class="px-4 py-3">${roleBadge(node.role)}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${sshString(node)}</td>
      <td class="px-4 py-3">${keyCell(node)}${syncBadge(node)}</td>
      <td class="px-4 py-3">${labelHtml}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${escapeHtml(node.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-duplicate="${escapeHtml(node.name)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-emerald-300" title="Duplicate">
          <i class="fa-solid fa-copy"></i>
        </button>
        <button data-delete="${escapeHtml(node.name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.rows.appendChild(row);
  });
}

function renderStatus(status) {
  if (!status) return;
  // Auto-save keeps working copy == disk, so the only interesting status is a
  // change made to swarm.tfvars outside the app.
  if (status.external_change) {
    els.driftMessage.textContent =
      "swarm.tfvars changed on disk outside the app.";
    els.driftBanner.style.display = "flex";
  } else {
    els.driftBanner.style.display = "none";
  }
}

function renderTfvars(text) {
  els.tfvars.textContent = text || "";
}

async function refreshTfvars() {
  try {
    const data = await api("/api/swarm/tfvars");
    renderTfvars(data.tfvars);
  } catch (err) {
    /* non-fatal */
  }
}

function resetForm() {
  els.origName.value = "";
  els.form.reset();
  els.port.value = "22";
  els.role.value = "";
  populateKeyOptions(defaultKeyValue());
  els.sshPassword.value = "";
  els.syncSsh.checked = false;
  els.labelByName.checked = true;
  applyLabelByName();
  els.formTitle.textContent = "Add node";
  els.saveBtn.hidden = false;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add node';
  els.cancelEdit.hidden = true;
  markAllRequired();
}

function startEdit(node) {
  els.origName.value = node.name;
  els.name.value = node.name;
  els.host.value = node.host;
  els.user.value = node.ssh_user;
  els.role.value = node.role;
  els.port.value = node.ssh_port;
  populateKeyOptions(node.ssh_key || "");
  els.sshPassword.value = node.ssh_password || "";
  els.syncSsh.checked = !!node.sync_ssh;
  els.labels.value = labelsToString(node.labels);
  const labelKeys = Object.keys(node.labels || {});
  els.labelByName.checked =
    labelKeys.length === 1 &&
    labelKeys[0] === "role" &&
    node.labels.role === node.name;
  applyLabelByName();
  els.formTitle.textContent = `Edit ${node.name}`;
  // No submit button while editing — changes auto-save as you type.
  els.saveBtn.hidden = true;
  els.cancelEdit.hidden = false;
  els.cancelEdit.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Done';
  markAllRequired();
  els.name.focus();
}

function buildPayload() {
  return {
    name: els.name.value.trim(),
    host: els.host.value.trim(),
    ssh_user: els.user.value.trim(),
    role: els.role.value,
    ssh_port: parseInt(els.port.value, 10) || 22,
    ssh_key: els.sshKey.value || "",
    ssh_password: els.sshPassword.value,
    sync_ssh: els.syncSsh.checked,
    labels: labelsFromForm(),
  };
}

// Auto-save the node currently being edited. Skips while the form is not a valid
// node so partial keystrokes don't blow away the on-disk value.
async function autosaveEdit() {
  const orig = els.origName.value;
  if (!orig) return;
  const payload = buildPayload();
  if (!payload.name || !payload.host) {
    setSaveState("error", "Name and host are required");
    return;
  }
  try {
    setSaveState("saving");
    const updated = await api(`/api/swarm/nodes/${encodeURIComponent(orig)}`, {
      method: "PUT",
      body: JSON.stringify(payload),
    });
    // The name is the key: keep the form pointed at the (possibly renamed) node.
    els.origName.value = updated.name;
    els.formTitle.textContent = `Edit ${updated.name}`;
    setSaveState("saved");
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveEditDebounced = debounce(autosaveEdit, 450);

// Pressing Enter (or clicking Add) commits: create a new node, or flush a pending
// edit immediately.
els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  if (isEditing()) {
    autosaveEdit();
    return;
  }
  const payload = buildPayload();
  try {
    await api("/api/swarm/nodes", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Added ${payload.name}`, "success");
    resetForm();
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.cancelEdit.addEventListener("click", resetForm);

// Auto-save text fields after a short debounce; commit selects immediately.
const textFields = [els.host, els.user, els.port, els.sshPassword, els.labels];
textFields.forEach((el) =>
  el.addEventListener("input", () => {
    if (isEditing()) autosaveEditDebounced();
  })
);
[els.role, els.sshKey, els.syncSsh].forEach((el) =>
  el.addEventListener("change", () => {
    if (isEditing()) autosaveEdit();
  })
);

// Live red-border feedback on required fields as they're typed/changed.
[els.name, els.host, els.user, els.labels].forEach((el) =>
  el.addEventListener("input", () => markRequired(el))
);
els.role.addEventListener("change", () => markRequired(els.role));

els.labelByName.addEventListener("change", () => {
  // Unchecking wipes the labels; checking mirrors the node name.
  if (!els.labelByName.checked) els.labels.value = "";
  applyLabelByName();
  if (isEditing()) autosaveEdit();
});

els.name.addEventListener("input", () => {
  if (els.labelByName.checked) applyLabelByName();
  if (isEditing()) autosaveEditDebounced();
});

// Pick a unique name for a duplicate: bump a trailing number (swarm-wk-0 ->
// swarm-wk-1), otherwise append -copy / -copy-N. Skips names already in use.
function nextNodeName(base) {
  const taken = new Set(currentNodes.map((n) => n.name));
  const match = base.match(/^(.*?)(\d+)$/);
  if (match) {
    const prefix = match[1];
    let n = parseInt(match[2], 10) + 1;
    while (taken.has(`${prefix}${n}`)) n += 1;
    return `${prefix}${n}`;
  }
  if (!taken.has(`${base}-copy`)) return `${base}-copy`;
  let i = 2;
  while (taken.has(`${base}-copy-${i}`)) i += 1;
  return `${base}-copy-${i}`;
}

// Duplicate a node with a fresh unique name, mirroring the naming convention:
// any host/label that echoes the old name is rewritten to the new one.
async function duplicateNode(node) {
  const newName = nextNodeName(node.name);
  const newHost =
    node.host && node.host.includes(node.name)
      ? node.host.split(node.name).join(newName)
      : node.host;
  const labels = {};
  Object.entries(node.labels || {}).forEach(([key, value]) => {
    labels[key] = value === node.name ? newName : value;
  });
  const payload = {
    name: newName,
    host: newHost,
    ssh_user: node.ssh_user,
    role: node.role,
    ssh_port: node.ssh_port,
    ssh_key: node.ssh_key || "",
    ssh_password: node.ssh_password || "",
    sync_ssh: !!node.sync_ssh,
    labels,
  };
  try {
    await api("/api/swarm/nodes", {
      method: "POST",
      body: JSON.stringify(payload),
    });
    toast(`Duplicated ${node.name} \u2192 ${newName}`, "success");
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const node = currentNodes.find((n) => n.name === editBtn.dataset.edit);
    if (node) startEdit(node);
    return;
  }
  const dupBtn = event.target.closest("[data-duplicate]");
  if (dupBtn) {
    const node = currentNodes.find((n) => n.name === dupBtn.dataset.duplicate);
    if (node) await duplicateNode(node);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete node "${delBtn.dataset.delete}"?`)) return;
    try {
      await api(`/api/swarm/nodes/${encodeURIComponent(delBtn.dataset.delete)}`, {
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
    const data = await api("/api/swarm/reload", { method: "POST" });
    renderNodes(data.nodes);
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
    toast("Copied swarm.tfvars to clipboard", "success");
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

// -- Apply / reconcile --------------------------------------------------------

let currentPlan = null;
let applyBusy = false;

const LOG_STYLES = {
  step: "text-sky-300 font-medium",
  cmd: "text-slate-500",
  ok: "text-emerald-300",
  warn: "text-amber-300",
  error: "text-rose-300",
  info: "text-slate-300",
};

function appendLog(level, message) {
  const line = document.createElement("div");
  line.className = LOG_STYLES[level] || LOG_STYLES.info;
  const prefix =
    level === "step" ? "\u25b8 " : level === "ok" ? "\u2713 " : level === "error" ? "\u2717 " : "";
  line.textContent = prefix + message;
  els.applyLog.appendChild(line);
  els.applyLog.scrollTop = els.applyLog.scrollHeight;
}

function setApplyBusy(busy) {
  applyBusy = busy;
  els.applyReplan.disabled = busy;
  updateRunEnabled();
}

function updateRunEnabled() {
  const plan = currentPlan;
  const runnable =
    !applyBusy &&
    plan &&
    !plan.errors.length &&
    plan.actions.length > 0 &&
    (!plan.destructive || els.applyConfirm.checked);
  els.applyRun.disabled = !runnable;
}

function renderPlan(plan) {
  currentPlan = plan;
  els.applyPlanWrap.style.display = "block";
  els.applyPlan.innerHTML = "";

  plan.errors.forEach((err) => {
    const li = document.createElement("li");
    li.className = "flex items-start gap-2 text-rose-300";
    li.innerHTML = `<i class="fa-solid fa-circle-xmark mt-0.5"></i><span>${escapeHtml(err)}</span>`;
    els.applyPlan.appendChild(li);
  });

  if (!plan.actions.length && !plan.errors.length) {
    const li = document.createElement("li");
    li.className = "flex items-center gap-2 text-emerald-300";
    li.innerHTML = `<i class="fa-solid fa-check"></i><span>No changes needed — the swarm matches the config.</span>`;
    els.applyPlan.appendChild(li);
  }

  plan.actions.forEach((action) => {
    const li = document.createElement("li");
    li.className = `flex items-start gap-2 ${action.destructive ? "text-rose-300" : "text-slate-200"}`;
    const icon = action.destructive ? "fa-triangle-exclamation" : "fa-plus";
    li.innerHTML = `<i class="fa-solid ${icon} mt-0.5"></i><span>${escapeHtml(action.title)}</span>`;
    els.applyPlan.appendChild(li);
  });

  plan.warnings.forEach((w) => {
    const li = document.createElement("li");
    li.className = "flex items-start gap-2 text-amber-300";
    li.innerHTML = `<i class="fa-solid fa-circle-info mt-0.5"></i><span>${escapeHtml(w)}</span>`;
    els.applyPlan.appendChild(li);
  });

  if (plan.destructive) {
    els.applyDestructive.style.display = "block";
    els.applyDestructiveText.textContent =
      plan.warnings.join(" ") ||
      "This plan removes nodes or rebuilds the swarm. Running services will be recreated.";
    els.applyConfirm.checked = false;
  } else {
    els.applyDestructive.style.display = "none";
  }
  updateRunEnabled();
}

function resetApplyModal() {
  currentPlan = null;
  els.applyLog.innerHTML = "";
  els.applyPlan.innerHTML = "";
  els.applyPlanWrap.style.display = "none";
  els.applyDestructive.style.display = "none";
  els.applyConfirm.checked = false;
  els.applyRun.disabled = true;
}

async function startPlan() {
  resetApplyModal();
  els.applyPhase.textContent = "· planning…";
  setApplyBusy(true);
  appendLog("step", "Planning…");
  try {
    await api("/api/swarm/plan", { method: "POST" });
  } catch (err) {
    appendLog("error", err.message);
    setApplyBusy(false);
  }
}

async function startApply() {
  els.applyPhase.textContent = "· applying…";
  setApplyBusy(true);
  appendLog("step", "Applying…");
  try {
    await api("/api/swarm/apply", {
      method: "POST",
      body: JSON.stringify({ confirm_destructive: els.applyConfirm.checked }),
    });
  } catch (err) {
    appendLog("error", err.message);
    setApplyBusy(false);
  }
}

els.applyBtn.addEventListener("click", () => {
  els.applyModal.style.display = "flex";
  resetApplyModal();
  // Go straight to applying so you can watch it work; the backend re-plans first
  // and only pauses (needs_confirm) if the plan turns out destructive.
  startApply();
});
els.applyReplan.addEventListener("click", startPlan);
els.applyRun.addEventListener("click", startApply);
els.applyConfirm.addEventListener("change", updateRunEnabled);
els.applyModal.addEventListener("click", (event) => {
  if (event.target === els.applyModal || event.target.closest("[data-close]")) {
    els.applyModal.style.display = "none";
  }
});

socket.on("swarm:apply:log", (data) => {
  if (!data) return;
  appendLog(data.level, data.message);
});
socket.on("swarm:apply:plan", (plan) => {
  renderPlan(plan);
});
socket.on("swarm:apply:done", (data) => {
  setApplyBusy(false);
  els.applyPhase.textContent = "";
  if (!data) return;
  if (data.phase === "apply") {
    if (data.ok) {
      toast("Swarm applied successfully", "success");
      refreshTfvars();
    } else if (data.needs_confirm) {
      appendLog("warn", "Confirm the destructive changes, then Apply again.");
    } else {
      toast("Apply finished with errors — see the log", "error");
    }
  }
});

socket.on("swarm:nodes", (nodes) => {
  renderNodes(nodes);
  refreshTfvars();
});
socket.on("swarm:status", renderStatus);
socket.on("ssh:sets", (snapshot) => {
  keySets = (snapshot.sets || []).map((s) => s.name);
  populateKeyOptions(els.sshKey.value || defaultKeyValue());
});

async function init() {
  applyLabelByName();
  markAllRequired();
  setSaveState("idle");
  try {
    await loadKeySets();
    const data = await api("/api/swarm/nodes");
    renderNodes(data.nodes);
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
