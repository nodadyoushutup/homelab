"use strict";

const socket = io();
const API = "/api/monitoring/grafana";
const CANONICAL_VM_URL = "http://victoriametrics:8428";

let datasources = [];

function $(id) {
  return document.getElementById(id);
}

let saveStateTimer;
function setSaveState(kind, message) {
  const el = $("save-state");
  clearTimeout(saveStateTimer);
  if (kind === "saving") {
    el.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    el.className = "text-sm text-sky-300";
  } else if (kind === "saved") {
    el.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    el.className = "text-sm text-emerald-300";
    saveStateTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    el.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(message || "Save failed")}`;
    el.className = "text-xs font-medium text-rose-300";
  } else {
    el.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    el.className = "text-sm text-slate-500";
  }
}

function escapeHtml(value) {
  return String(value ?? "").replace(/[&<>"']/g, (ch) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

async function api(path, options = {}) {
  const response = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

function toast(message, kind = "info") {
  const palette = {
    info: "bg-slate-800 text-slate-100 border-slate-700",
    success: "bg-emerald-500/15 text-emerald-200 border-emerald-500/40",
    error: "bg-rose-500/15 text-rose-200 border-rose-500/40",
  };
  const el = document.createElement("div");
  el.className = `pointer-events-auto rounded-lg border px-4 py-2 text-sm shadow-lg ${palette[kind] || palette.info}`;
  el.textContent = message;
  document.getElementById("toast-root").appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 300ms";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 300);
  }, 2600);
}

function badge(text, tone) {
  const tones = { on: "bg-emerald-500/15 text-emerald-300", off: "bg-slate-700/50 text-slate-400" };
  return `<span class="rounded-full px-2 py-0.5 text-xs font-medium ${tones[tone] || tones.off}">${escapeHtml(text)}</span>`;
}

function render() {
  $("count").textContent = datasources.length ? `(${datasources.length})` : "";
  $("empty").hidden = datasources.length > 0;
  $("rows").innerHTML = datasources
    .map((d) => {
      const jd = Object.keys(d.json_data || {}).length
        ? `<div class="font-mono text-xs text-slate-600">${escapeHtml(Object.entries(d.json_data).map(([k, v]) => `${k}=${v}`).join(", "))}</div>`
        : "";
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3"><div class="font-medium text-slate-100">${escapeHtml(d.name)}</div><div class="font-mono text-xs text-slate-500">${escapeHtml(d.uid)}</div></td>
        <td class="px-4 py-3 text-slate-300">${escapeHtml(d.type)}</td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(d.url)}${jd}</td>
        <td class="px-4 py-3">${d.is_default ? badge("default", "on") : badge("no", "off")}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <button data-edit="${escapeHtml(d.uid)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-orange-300" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button data-del="${escapeHtml(d.uid)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>
        </td></tr>`;
    })
    .join("");
}

function renderStatus(status) {
  if (!status) return;
  $("drift-banner").style.display = status.external_change ? "flex" : "none";
}

async function refreshTfvars() {
  try {
    const data = await api(`${API}/tfvars`);
    $("tfvars-preview").textContent = data.tfvars || "";
  } catch (err) {
    /* non-fatal */
  }
}

function openModal(id) {
  $(id).style.display = "flex";
}
function closeModal(el) {
  el.style.display = "none";
}

function addJdRow(key, value) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-f="key" value="${escapeHtml(key || "")}" placeholder="httpMethod" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-f="value" value="${escapeHtml(value == null ? "" : value)}" placeholder="POST" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-row class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  $("ds-jd-rows").appendChild(tr);
}

function collectJd() {
  const out = {};
  $("ds-jd-rows").querySelectorAll("tr").forEach((tr) => {
    const key = tr.querySelector('[data-f="key"]').value.trim();
    const value = tr.querySelector('[data-f="value"]').value.trim();
    if (key) out[key] = value;
  });
  return out;
}

function updateUrlHint() {
  const isProm = $("ds-uid").value.trim() === "prometheus";
  const bad = isProm && $("ds-url").value.trim() !== CANONICAL_VM_URL;
  $("ds-url-hint").classList.toggle("hidden", !bad);
}

function openDs(d) {
  $("ds-orig").value = d ? d.uid : "";
  $("ds-name").value = d ? d.name : "";
  $("ds-uid").value = d ? d.uid : "";
  $("ds-type").value = d ? d.type : "";
  $("ds-url").value = d ? d.url : "";
  $("ds-is_default").checked = Boolean(d && d.is_default);
  $("ds-jd-rows").innerHTML = "";
  Object.entries((d && d.json_data) || {}).forEach(([k, v]) => addJdRow(k, v));
  $("ds-title").textContent = d ? `Edit ${d.name}` : "Add data source";
  updateUrlHint();
  openModal("modal-ds");
}

function dsPayload() {
  return {
    name: $("ds-name").value.trim(),
    uid: $("ds-uid").value.trim(),
    type: $("ds-type").value.trim(),
    url: $("ds-url").value.trim(),
    is_default: $("ds-is_default").checked,
    json_data: collectJd(),
  };
}

$("ds-add-jd").addEventListener("click", () => addJdRow("", ""));
$("ds-jd-rows").addEventListener("click", (e) => {
  const btn = e.target.closest("[data-remove-row]");
  if (btn) btn.closest("tr").remove();
});
["ds-uid", "ds-url"].forEach((id) => $(id).addEventListener("input", updateUrlHint));

$("ds-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const orig = $("ds-orig").value;
  const payload = dsPayload();
  try {
    setSaveState("saving");
    if (orig) {
      await api(`${API}/datasources/${encodeURIComponent(orig)}`, { method: "PUT", body: JSON.stringify(payload) });
      toast(`Saved ${payload.name}`, "success");
    } else {
      await api(`${API}/datasources`, { method: "POST", body: JSON.stringify(payload) });
      toast(`Added ${payload.name}`, "success");
    }
    setSaveState("saved");
    closeModal($("modal-ds"));
    refreshTfvars();
  } catch (err) {
    setSaveState("error", err.message);
    toast(err.message, "error");
  }
});

$("add-btn").addEventListener("click", () => openDs(null));
$("rows").addEventListener("click", (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const d = datasources.find((x) => String(x.uid) === editBtn.dataset.edit);
    if (d) openDs(d);
    return;
  }
  const delBtn = event.target.closest("[data-del]");
  if (delBtn) {
    const key = delBtn.dataset.del;
    if (!confirm(`Delete data source "${key}"?`)) return;
    api(`${API}/datasources/${encodeURIComponent(key)}`, { method: "DELETE" })
      .then(() => {
        toast(`Deleted ${key}`, "success");
        refreshTfvars();
      })
      .catch((err) => toast(err.message, "error"));
  }
});

document.querySelectorAll("[data-close]").forEach((btn) =>
  btn.addEventListener("click", () => {
    const modal = btn.closest(".fixed");
    if (modal) closeModal(modal);
  })
);
document.querySelectorAll(".fixed").forEach((modal) =>
  modal.addEventListener("click", (event) => {
    if (event.target === modal) closeModal(modal);
  })
);
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape") document.querySelectorAll(".fixed").forEach((m) => closeModal(m));
});

async function doReload() {
  try {
    const data = await api(`${API}/reload`, { method: "POST" });
    datasources = data.datasources || [];
    render();
    renderStatus(data.status);
    refreshTfvars();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}
$("reload-btn").addEventListener("click", doReload);
$("drift-reload").addEventListener("click", doReload);

$("preview-btn").addEventListener("click", async () => {
  await refreshTfvars();
  openModal("modal-preview");
});
$("preview-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("tfvars-preview").textContent || "");
    toast("Copied config.tfvars to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});

socket.on("grafana_config:config", (payload) => {
  datasources = (payload && payload.datasources) || [];
  render();
  refreshTfvars();
});
socket.on("grafana_config:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api(`${API}/config`);
    datasources = data.datasources || [];
    render();
    renderStatus(data.status);
    refreshTfvars();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
