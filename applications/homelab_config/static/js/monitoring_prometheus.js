"use strict";

const socket = io();
const API = "/api/monitoring/prometheus";

let config = { global: { extra: {} }, remote_write: [], scrape_configs: [] };

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

function debounce(fn, ms) {
  let t;
  return (...a) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...a), ms);
  };
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

function jsyaml(obj) {
  // Minimal YAML for the advanced textarea: prefer server round-trip, but for
  // display we dump simple structures. Falls back to JSON if complex.
  return obj && Object.keys(obj).length ? JSON.stringify(obj, null, 2) : "";
}

function targetCount(job) {
  return (job.static_configs || []).reduce((n, sc) => n + (sc.targets || []).length, 0);
}

// --- render ----------------------------------------------------------------

function renderGlobal() {
  if (!(document.activeElement && document.activeElement.id.startsWith("g-"))) {
    $("g-scrape_interval").value = config.global.scrape_interval || "";
    $("g-evaluation_interval").value = config.global.evaluation_interval || "";
  }
}

function renderRemoteWrite() {
  const active = document.activeElement && document.activeElement.closest && document.activeElement.closest("#rw-list");
  if (active) return;
  $("rw-list").innerHTML = "";
  (config.remote_write || []).forEach((entry, idx) => {
    const row = document.createElement("div");
    row.className = "flex items-center gap-2";
    row.innerHTML = `
      <input data-rw="${idx}" value="${escapeHtml(entry.url)}" placeholder="http://victoriametrics:8428/api/v1/write" class="mon-input font-mono text-xs" />
      <button type="button" data-rw-del="${idx}" class="rounded-md px-2 py-2 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button>`;
    $("rw-list").appendChild(row);
  });
}

function renderJobs() {
  const jobs = config.scrape_configs || [];
  $("count").textContent = jobs.length ? `(${jobs.length})` : "";
  $("empty").hidden = jobs.length > 0;
  $("rows").innerHTML = jobs
    .map((job, idx) => {
      const adv = Object.keys(job.extra || {}).length
        ? `<span class="rounded-full bg-fuchsia-500/15 px-2 py-0.5 text-xs font-medium text-fuchsia-300">${escapeHtml(Object.keys(job.extra).join(", "))}</span>`
        : '<span class="text-slate-600">—</span>';
      return `<tr class="hover:bg-slate-800/40">
        <td class="px-4 py-3 font-medium text-slate-100">${escapeHtml(job.job_name)}</td>
        <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(job.metrics_path || "/metrics")}${job.scheme ? " · " + escapeHtml(job.scheme) : ""}</td>
        <td class="px-4 py-3 text-slate-300">${targetCount(job)} target(s)</td>
        <td class="px-4 py-3">${adv}</td>
        <td class="px-4 py-3 text-right whitespace-nowrap">
          <button data-edit="${idx}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-red-300" title="Edit"><i class="fa-solid fa-pen"></i></button>
          <button data-del="${escapeHtml(job.job_name)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>
        </td></tr>`;
    })
    .join("");
}

function renderAll() {
  renderGlobal();
  renderRemoteWrite();
  renderJobs();
}

function renderStatus(status) {
  if (!status) return;
  $("drift-banner").style.display = status.external_change ? "flex" : "none";
}

async function refreshYaml() {
  try {
    const data = await api(`${API}/yaml`);
    $("yaml-preview").textContent = data.yaml || "";
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

// --- global + remote_write autosave ----------------------------------------

async function saveGlobal() {
  try {
    setSaveState("saving");
    config.global.scrape_interval = $("g-scrape_interval").value.trim();
    config.global.evaluation_interval = $("g-evaluation_interval").value.trim();
    await api(`${API}/global`, {
      method: "PUT",
      body: JSON.stringify({
        scrape_interval: config.global.scrape_interval,
        evaluation_interval: config.global.evaluation_interval,
        extra: config.global.extra || {},
      }),
    });
    setSaveState("saved");
    refreshYaml();
  } catch (err) {
    setSaveState("error", err.message);
  }
}
const saveGlobalDebounced = debounce(saveGlobal, 600);
["g-scrape_interval", "g-evaluation_interval"].forEach((id) =>
  $(id).addEventListener("input", saveGlobalDebounced)
);

async function saveRemoteWrite() {
  try {
    setSaveState("saving");
    const urls = [];
    $("rw-list")
      .querySelectorAll("[data-rw]")
      .forEach((input) => {
        const idx = Number(input.dataset.rw);
        const url = input.value.trim();
        if (url) urls.push({ url, extra: (config.remote_write[idx] || {}).extra || {} });
      });
    const saved = await api(`${API}/remote_write`, {
      method: "PUT",
      body: JSON.stringify({ urls }),
    });
    config.remote_write = saved;
    setSaveState("saved");
    refreshYaml();
  } catch (err) {
    setSaveState("error", err.message);
  }
}
const saveRemoteWriteDebounced = debounce(saveRemoteWrite, 600);
$("rw-list").addEventListener("input", (e) => {
  if (e.target.matches("[data-rw]")) saveRemoteWriteDebounced();
});
$("rw-list").addEventListener("click", (e) => {
  const del = e.target.closest("[data-rw-del]");
  if (del) {
    config.remote_write.splice(Number(del.dataset.rwDel), 1);
    renderRemoteWrite();
    saveRemoteWrite();
  }
});
$("rw-add").addEventListener("click", () => {
  config.remote_write.push({ url: "", extra: {} });
  renderRemoteWrite();
});

// --- job modal (nested groups + labels) -------------------------------------

function addLabelRow(tbody, key, value) {
  const tr = document.createElement("tr");
  tr.innerHTML = `
    <td class="px-2 py-1"><input data-label-key value="${escapeHtml(key || "")}" placeholder="platform" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1"><input data-label-val value="${escapeHtml(value == null ? "" : value)}" placeholder="docker" class="w-full rounded border border-slate-700 bg-slate-950 px-2 py-1 font-mono text-slate-100" /></td>
    <td class="px-2 py-1 text-right"><button type="button" data-remove-label class="rounded px-2 py-1 text-slate-400 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button></td>`;
  tbody.appendChild(tr);
}

function addGroup(sc) {
  const tpl = $("group-template").content.cloneNode(true);
  const group = tpl.querySelector("[data-group]");
  group.querySelector("[data-targets]").value = ((sc && sc.targets) || []).join("\n");
  const labels = group.querySelector("[data-labels]");
  Object.entries((sc && sc.labels) || {}).forEach(([k, v]) => addLabelRow(labels, k, v));
  $("job-groups").appendChild(group);
}

$("job-add-group").addEventListener("click", () => addGroup(null));
$("job-groups").addEventListener("click", (e) => {
  const rmGroup = e.target.closest("[data-remove-group]");
  if (rmGroup) {
    rmGroup.closest("[data-group]").remove();
    return;
  }
  const addLabel = e.target.closest("[data-add-label]");
  if (addLabel) {
    addLabelRow(addLabel.closest("[data-group]").querySelector("[data-labels]"), "", "");
    return;
  }
  const rmLabel = e.target.closest("[data-remove-label]");
  if (rmLabel) rmLabel.closest("tr").remove();
});

function openJob(job) {
  $("job-orig").value = job ? job.job_name : "";
  $("job-job_name").value = job ? job.job_name : "";
  $("job-metrics_path").value = job ? job.metrics_path || "" : "";
  $("job-scheme").value = job ? job.scheme || "" : "";
  $("job-scrape_interval").value = job ? job.scrape_interval || "" : "";
  $("job-scrape_timeout").value = job ? job.scrape_timeout || "" : "";
  $("job-extra").value = job ? jsyaml(job.extra) : "";
  $("job-groups").innerHTML = "";
  ((job && job.static_configs) || []).forEach((sc) => addGroup(sc));
  if (!job) addGroup(null);
  $("job-title").textContent = job ? `Edit ${job.job_name}` : "Add scrape job";
  openModal("modal-job");
}

function collectJob() {
  const static_configs = [];
  $("job-groups")
    .querySelectorAll("[data-group]")
    .forEach((group) => {
      const targets = group
        .querySelector("[data-targets]")
        .value.split("\n")
        .join(",")
        .split(",")
        .map((t) => t.trim())
        .filter(Boolean);
      const labels = {};
      group.querySelectorAll("[data-labels] tr").forEach((tr) => {
        const key = tr.querySelector("[data-label-key]").value.trim();
        const val = tr.querySelector("[data-label-val]").value.trim();
        if (key) labels[key] = val;
      });
      if (targets.length || Object.keys(labels).length) static_configs.push({ targets, labels });
    });
  let extra = {};
  const extraText = $("job-extra").value.trim();
  if (extraText) {
    try {
      extra = JSON.parse(extraText);
    } catch (e) {
      // Not JSON: send raw text; the server parses it as YAML.
      extra = extraText;
    }
  }
  return {
    job_name: $("job-job_name").value.trim(),
    metrics_path: $("job-metrics_path").value.trim(),
    scheme: $("job-scheme").value.trim(),
    scrape_interval: $("job-scrape_interval").value.trim(),
    scrape_timeout: $("job-scrape_timeout").value.trim(),
    static_configs,
    extra,
  };
}

$("job-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const orig = $("job-orig").value;
  const payload = collectJob();
  try {
    setSaveState("saving");
    if (orig) {
      await api(`${API}/jobs/${encodeURIComponent(orig)}`, { method: "PUT", body: JSON.stringify(payload) });
      toast(`Saved ${payload.job_name}`, "success");
    } else {
      await api(`${API}/jobs`, { method: "POST", body: JSON.stringify(payload) });
      toast(`Added ${payload.job_name}`, "success");
    }
    setSaveState("saved");
    closeModal($("modal-job"));
    refreshYaml();
  } catch (err) {
    setSaveState("error", err.message);
    toast(err.message, "error");
  }
});

$("add-btn").addEventListener("click", () => openJob(null));
$("rows").addEventListener("click", (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const job = config.scrape_configs[Number(editBtn.dataset.edit)];
    if (job) openJob(job);
    return;
  }
  const delBtn = event.target.closest("[data-del]");
  if (delBtn) {
    const key = delBtn.dataset.del;
    if (!confirm(`Delete scrape job "${key}"?`)) return;
    api(`${API}/jobs/${encodeURIComponent(key)}`, { method: "DELETE" })
      .then(() => {
        toast(`Deleted ${key}`, "success");
        refreshYaml();
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
    config = data.config;
    renderAll();
    renderStatus(data.status);
    refreshYaml();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}
$("reload-btn").addEventListener("click", doReload);
$("drift-reload").addEventListener("click", doReload);

$("preview-btn").addEventListener("click", async () => {
  await refreshYaml();
  openModal("modal-preview");
});
$("preview-copy").addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText($("yaml-preview").textContent || "");
    toast("Copied prometheus.yaml to clipboard", "success");
  } catch (err) {
    toast("Could not copy to clipboard", "error");
  }
});

socket.on("prometheus_config:config", (payload) => {
  config = payload || config;
  renderAll();
  refreshYaml();
});
socket.on("prometheus_config:status", renderStatus);

async function init() {
  setSaveState("idle");
  try {
    const data = await api(`${API}/config`);
    config = data.config;
    renderAll();
    renderStatus(data.status);
    refreshYaml();
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
