"use strict";

const socket = io();

const els = {
  tabBar: document.getElementById("tab-bar"),
  form: document.getElementById("jenkins-form"),
  root: document.getElementById("form-root"),
  saveState: document.getElementById("save-state"),
  previewBtn: document.getElementById("preview-btn"),
  reloadBtn: document.getElementById("reload-btn"),
  previewModal: document.getElementById("modal-preview"),
  previewPath: document.getElementById("preview-path"),
  previewCopy: document.getElementById("preview-copy"),
  tfvars: document.getElementById("tfvars-preview"),
  driftBanner: document.getElementById("drift-banner"),
  driftMessage: document.getElementById("drift-message"),
  driftReload: document.getElementById("drift-reload"),
};

const state = {
  slices: [], // [{key, title, kind}]
  active: null,
  configs: {}, // key -> config
  statuses: {}, // key -> {dirty, external_change, disk_present}
};

let hydrating = false;

function debounce(fn, ms) {
  let t;
  return (...a) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...a), ms);
  };
}

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

let saveTimer;
function setSaveState(kind, message) {
  clearTimeout(saveTimer);
  if (kind === "saving") {
    els.saveState.innerHTML = '<i class="fa-solid fa-circle-notch fa-spin"></i>';
    els.saveState.className = "text-sm text-sky-300";
  } else if (kind === "saved") {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud-arrow-up"></i>';
    els.saveState.className = "text-sm text-emerald-300";
    saveTimer = setTimeout(() => setSaveState("idle"), 1000);
  } else if (kind === "error") {
    els.saveState.innerHTML = `<i class="fa-solid fa-triangle-exclamation mr-1 text-rose-400"></i>${escapeHtml(
      message || "Save failed"
    )}`;
    els.saveState.className = "text-xs font-medium text-rose-300";
  } else {
    els.saveState.innerHTML = '<i class="fa-solid fa-cloud"></i>';
    els.saveState.className = "text-sm text-slate-500";
  }
}

async function api(path, options = {}) {
  const res = await fetch(path, {
    headers: { "Content-Type": "application/json" },
    ...options,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(data.error || `Request failed (${res.status})`);
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

// --- small HTML field builders ----------------------------------------------

const inputCls =
  "w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 text-slate-100 focus:border-sky-500 focus:outline-none";
const inputMono =
  "w-full rounded-lg border border-slate-700 bg-slate-950 px-3 py-2 font-mono text-xs text-slate-100 focus:border-sky-500 focus:outline-none";

function card(title, subtitle, inner) {
  return `<div class="rounded-xl border border-slate-800 bg-slate-900/50 p-5">
    <h2 class="text-sm font-semibold uppercase tracking-wide text-slate-400">${escapeHtml(
      title
    )}</h2>
    ${
      subtitle
        ? `<p class="mt-1 mb-4 text-xs text-slate-500">${escapeHtml(subtitle)}</p>`
        : '<div class="mb-4"></div>'
    }
    ${inner}
  </div>`;
}

function textField(id, label, value, opts = {}) {
  const cls = opts.mono ? inputMono : inputCls;
  const type = opts.type || "text";
  return `<label class="block text-sm">
    <span class="mb-1 block text-slate-300">${escapeHtml(label)}${
    opts.optional ? ' <span class="text-slate-500">(optional)</span>' : ""
  }</span>
    <input id="${id}" type="${type}" value="${escapeHtml(value ?? "")}" placeholder="${escapeHtml(
    opts.placeholder || ""
  )}" class="${cls}" />
    ${
      opts.help
        ? `<span class="mt-1 block text-xs text-slate-500">${escapeHtml(opts.help)}</span>`
        : ""
    }
  </label>`;
}

function textareaListField(id, label, arr, opts = {}) {
  return `<label class="block text-sm">
    <span class="mb-1 block text-slate-300">${escapeHtml(label)}</span>
    <textarea id="${id}" rows="${opts.rows || 3}" placeholder="${escapeHtml(
    opts.placeholder || ""
  )}" class="${inputMono}">${escapeHtml((arr || []).join("\n"))}</textarea>
    ${
      opts.help
        ? `<span class="mt-1 block text-xs text-slate-500">${escapeHtml(opts.help)}</span>`
        : ""
    }
  </label>`;
}

function envRow(key, value) {
  return `<div data-row class="mb-2 flex items-center gap-2">
    <input class="env-key ${inputMono} flex-1" placeholder="KEY" value="${escapeHtml(
    key
  )}" />
    <span class="text-slate-500">=</span>
    <input class="env-value ${inputMono} flex-1" placeholder="value" value="${escapeHtml(
    value
  )}" />
    <button type="button" data-action="del-row" class="rounded-md px-2 py-1 text-slate-500 hover:bg-slate-800 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button>
  </div>`;
}

function envEditor(id, pairs, addAction, title) {
  const rows = (pairs || []).map((p) => envRow(p.key, p.value)).join("");
  return `<div>
    <span class="mb-2 block text-sm text-slate-300">${escapeHtml(title || "Environment")}</span>
    <div id="${id}">${rows}</div>
    <button type="button" data-action="${addAction}" class="mt-1 rounded-md border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"><i class="fa-solid fa-plus mr-1"></i>Add variable</button>
  </div>`;
}

function platRow(os, arch) {
  return `<div data-row class="mb-2 flex items-center gap-2">
    <input class="p-os ${inputMono} flex-1" placeholder="os (e.g. linux)" value="${escapeHtml(
    os
  )}" />
    <input class="p-arch ${inputMono} flex-1" placeholder="architecture (e.g. amd64)" value="${escapeHtml(
    arch
  )}" />
    <button type="button" data-action="del-row" class="rounded-md px-2 py-1 text-slate-500 hover:bg-slate-800 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button>
  </div>`;
}

function optsToText(pairs) {
  return (pairs || []).map((p) => `${p.key}=${p.value}`).join(", ");
}

function mountRow(m) {
  m = m || { name: "", target: "", driver: "", no_copy: false, driver_opts: [] };
  return `<div data-row class="mb-3 rounded-lg border border-slate-800 p-3">
    <div class="grid gap-2 sm:grid-cols-3">
      <input class="m-name ${inputMono}" placeholder="name" value="${escapeHtml(m.name)}" />
      <input class="m-target ${inputMono}" placeholder="target" value="${escapeHtml(
    m.target
  )}" />
      <input class="m-driver ${inputMono}" placeholder="driver (e.g. local)" value="${escapeHtml(
    m.driver
  )}" />
    </div>
    <div class="mt-2 flex items-center gap-3">
      <input class="m-opts ${inputMono} flex-1" placeholder="driver_opts: k=v, k2=v2" value="${escapeHtml(
    optsToText(m.driver_opts)
  )}" />
      <label class="flex items-center gap-2 text-xs text-slate-300 whitespace-nowrap">
        <input type="checkbox" class="m-nocopy" ${m.no_copy ? "checked" : ""} /> no_copy
      </label>
      <button type="button" data-action="del-row" class="rounded-md px-2 py-1 text-slate-500 hover:bg-slate-800 hover:text-rose-300"><i class="fa-solid fa-xmark"></i></button>
    </div>
  </div>`;
}

// --- form rendering ----------------------------------------------------------

function coreCards(cfg) {
  const targeting = card(
    "Deploy target",
    "Which Docker/Swarm machine and DNS this slice deploys through.",
    `<div class="space-y-4">
      ${textField("f-docker_machine", "Docker machine", cfg.docker_machine, {
        mono: true,
        placeholder: "swarm-cp-0",
        help: "Selects an entry from the shared docker providers catalog.",
      })}
      ${textareaListField("f-dns_nameservers", "DNS nameservers", cfg.dns_nameservers, {
        placeholder: "1.1.1.1",
        help: "One nameserver per line.",
      })}
    </div>`
  );
  const nfs = card(
    "NFS",
    "Selects a share from the shared NFS catalog and where to mount it.",
    `<div class="grid gap-4 sm:grid-cols-3">
      ${textField("f-nfs_share", "Share (catalog key)", cfg.nfs_share, { placeholder: "code" })}
      ${textField("f-nfs_subpath", "Subpath", cfg.nfs_subpath, { mono: true, placeholder: "/homelab" })}
      ${textField("f-nfs_mount_target", "Mount target", cfg.nfs_mount_target, { mono: true })}
    </div>`
  );
  return targeting + nfs;
}

function renderForm(key) {
  const cfg = state.configs[key];
  if (!cfg) {
    els.root.innerHTML = "";
    return;
  }
  const slice = state.slices.find((s) => s.key === key);
  const kind = slice ? slice.kind : "agent";
  hydrating = true;

  let html = coreCards(cfg);

  if (kind === "controller") {
    html += card(
      "Controller",
      "Published ports, JCasC config path, shared config volume.",
      `<div class="grid gap-4 sm:grid-cols-2">
        ${textField("f-controller_published_port", "Controller published port", cfg.controller_published_port, {
          type: "number",
          placeholder: "18082",
        })}
        ${textField("f-agent_published_port", "Agent published port", cfg.agent_published_port, {
          type: "number",
          placeholder: "50000",
        })}
        ${textField("f-casc_config_path", "JCasC config path", cfg.casc_config_path, {
          mono: true,
          optional: true,
        })}
        ${textField("f-shared_tfvars_volume_name", "Shared config volume name", cfg.shared_tfvars_volume_name, {
          mono: true,
          optional: true,
        })}
      </div>`
    );
    html += card(
      "Environment",
      "Container environment variables (env map).",
      envEditor("env-rows", cfg.env, "add-env")
    );
    html += card(
      "Extra mounts",
      "Optional mount definitions appended after the default Jenkins mounts.",
      `<div id="mount-rows">${(cfg.mounts || []).map(mountRow).join("")}</div>
       <button type="button" data-action="add-mount" class="mt-1 rounded-md border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"><i class="fa-solid fa-plus mr-1"></i>Add mount</button>`
    );
    html += card(
      "Placement",
      "Optional Swarm placement constraints and platforms (left empty = unconstrained).",
      `${textareaListField("f-placement_constraints", "Constraints", cfg.placement.constraints, {
        placeholder: "node.role==manager",
        help: "One constraint per line.",
      })}
      <div class="mt-4">
        <span class="mb-2 block text-sm text-slate-300">Platforms</span>
        <div id="plat-rows">${(cfg.placement.platforms || [])
          .map((p) => platRow(p.os, p.architecture))
          .join("")}</div>
        <button type="button" data-action="add-plat" class="mt-1 rounded-md border border-slate-700 px-3 py-1 text-xs text-slate-300 hover:bg-slate-800"><i class="fa-solid fa-plus mr-1"></i>Add platform</button>
      </div>`
    );
  } else {
    html += card(
      "Agent",
      "Controller URL and the JCasC label filter that selects this pool's nodes.",
      `<div class="space-y-4">
        ${textField("f-jenkins_url", "Jenkins controller URL", cfg.jenkins_url, {
          mono: true,
          placeholder: "http://jenkins:8080",
        })}
        ${textareaListField("f-agent_label_filter", "Agent label filter", cfg.agent_label_filter, {
          rows: 2,
          placeholder: "amd64",
          help: "One label token per line.",
        })}
        ${textField("f-casc_config_path", "JCasC config path", cfg.casc_config_path, {
          mono: true,
          optional: true,
        })}
      </div>`
    );
    html += card(
      "Environment",
      "Container environment variables (env map).",
      envEditor("env-rows", cfg.env, "add-env")
    );
  }

  els.root.innerHTML = html;
  hydrating = false;
}

function linesToList(text) {
  return String(text || "")
    .split("\n")
    .map((l) => l.trim())
    .filter(Boolean);
}

function textToOpts(text) {
  const out = [];
  const seen = new Set();
  String(text || "")
    .split(",")
    .forEach((chunk) => {
      const idx = chunk.indexOf("=");
      if (idx < 0) return;
      const k = chunk.slice(0, idx).trim();
      const v = chunk.slice(idx + 1).trim();
      if (k && !seen.has(k)) {
        seen.add(k);
        out.push({ key: k, value: v });
      }
    });
  return out;
}

function val(id) {
  const el = document.getElementById(id);
  return el ? el.value.trim() : "";
}

function collectEnv() {
  return Array.from(document.querySelectorAll("#env-rows [data-row]"))
    .map((row) => ({
      key: row.querySelector(".env-key").value.trim(),
      value: row.querySelector(".env-value").value,
    }))
    .filter((p) => p.key);
}

function buildPayload(key) {
  const slice = state.slices.find((s) => s.key === key);
  const kind = slice ? slice.kind : "agent";
  const payload = {
    docker_machine: val("f-docker_machine"),
    dns_nameservers: linesToList(val("f-dns_nameservers")),
    nfs_share: val("f-nfs_share"),
    nfs_subpath: val("f-nfs_subpath"),
    nfs_mount_target: val("f-nfs_mount_target"),
    casc_config_path: val("f-casc_config_path"),
    env: collectEnv(),
  };
  if (kind === "controller") {
    payload.controller_published_port = val("f-controller_published_port");
    payload.agent_published_port = val("f-agent_published_port");
    payload.shared_tfvars_volume_name = val("f-shared_tfvars_volume_name");
    payload.mounts = Array.from(
      document.querySelectorAll("#mount-rows [data-row]")
    ).map((row) => ({
      name: row.querySelector(".m-name").value.trim(),
      target: row.querySelector(".m-target").value.trim(),
      driver: row.querySelector(".m-driver").value.trim(),
      no_copy: row.querySelector(".m-nocopy").checked,
      driver_opts: textToOpts(row.querySelector(".m-opts").value),
    }));
    payload.placement = {
      constraints: linesToList(val("f-placement_constraints")),
      platforms: Array.from(
        document.querySelectorAll("#plat-rows [data-row]")
      ).map((row) => ({
        os: row.querySelector(".p-os").value.trim(),
        architecture: row.querySelector(".p-arch").value.trim(),
      })),
    };
  } else {
    payload.jenkins_url = val("f-jenkins_url");
    payload.agent_label_filter = linesToList(val("f-agent_label_filter"));
  }
  return payload;
}

async function autosave() {
  if (hydrating || !state.active) return;
  const key = state.active;
  try {
    setSaveState("saving");
    const record = await api(`/api/cicd/jenkins/${key}/config`, {
      method: "PUT",
      body: JSON.stringify(buildPayload(key)),
    });
    state.configs[key] = record;
    setSaveState("saved");
    refreshTfvarsIfOpen();
  } catch (err) {
    setSaveState("error", err.message);
  }
}

const autosaveDebounced = debounce(autosave, 450);

// --- tabs --------------------------------------------------------------------

function renderTabs() {
  els.tabBar.innerHTML = state.slices
    .map((s) => {
      const st = state.statuses[s.key] || {};
      const activeCls =
        s.key === state.active
          ? "border-sky-400 text-sky-300"
          : "border-transparent text-slate-400 hover:text-slate-200";
      const dot = st.external_change
        ? '<span class="ml-2 inline-block h-2 w-2 rounded-full bg-amber-400" title="changed on disk"></span>'
        : "";
      return `<button type="button" data-tab="${s.key}" class="-mb-px border-b-2 px-4 py-2 text-sm font-medium transition ${activeCls}">${escapeHtml(
        s.title
      )}${dot}</button>`;
    })
    .join("");
}

function renderDrift() {
  const st = state.statuses[state.active] || {};
  els.driftBanner.style.display = st.external_change ? "flex" : "none";
}

function activate(key) {
  state.active = key;
  renderTabs();
  renderForm(key);
  renderDrift();
}

// --- preview -----------------------------------------------------------------

let previewOpen = false;

async function refreshTfvars() {
  if (!state.active) return;
  try {
    const data = await api(`/api/cicd/jenkins/${state.active}/tfvars`);
    els.tfvars.textContent = data.tfvars || "";
    const slice = state.slices.find((s) => s.key === state.active);
    els.previewPath.textContent = `.config/terraform/components/swarm/${
      slice && slice.key === "controller"
        ? "jenkins-controller"
        : "jenkins-" + (state.active || "")
    }/app.tfvars`;
  } catch (err) {
    /* non-fatal */
  }
}

function refreshTfvarsIfOpen() {
  if (previewOpen) refreshTfvars();
}

// --- events ------------------------------------------------------------------

els.tabBar.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-tab]");
  if (btn) activate(btn.dataset.tab);
});

els.root.addEventListener("input", () => {
  if (!hydrating) autosaveDebounced();
});

els.root.addEventListener("click", (e) => {
  const btn = e.target.closest("[data-action]");
  if (!btn) return;
  const action = btn.dataset.action;
  if (action === "del-row") {
    const row = e.target.closest("[data-row]");
    if (row) row.remove();
    autosaveDebounced();
  } else if (action === "add-env") {
    document.getElementById("env-rows").insertAdjacentHTML("beforeend", envRow("", ""));
  } else if (action === "add-mount") {
    document.getElementById("mount-rows").insertAdjacentHTML("beforeend", mountRow());
  } else if (action === "add-plat") {
    document.getElementById("plat-rows").insertAdjacentHTML("beforeend", platRow("", ""));
  }
});

els.form.addEventListener("submit", (e) => {
  e.preventDefault();
  autosave();
});

async function doReload() {
  if (!state.active) return;
  try {
    const data = await api(`/api/cicd/jenkins/${state.active}/reload`, { method: "POST" });
    state.configs[state.active] = data.config;
    state.statuses[state.active] = data.status;
    renderForm(state.active);
    renderTabs();
    renderDrift();
    refreshTfvarsIfOpen();
    toast("Reloaded from disk", "success");
  } catch (err) {
    toast(err.message, "error");
  }
}

els.reloadBtn.addEventListener("click", doReload);
els.driftReload.addEventListener("click", doReload);

els.previewBtn.addEventListener("click", async () => {
  await refreshTfvars();
  previewOpen = true;
  els.previewModal.style.display = "flex";
});
els.previewCopy.addEventListener("click", async () => {
  try {
    await navigator.clipboard.writeText(els.tfvars.textContent || "");
    toast("Copied to clipboard", "success");
  } catch (err) {
    toast("Could not copy", "error");
  }
});
els.previewModal.addEventListener("click", (e) => {
  if (e.target === els.previewModal || e.target.closest("[data-close]")) {
    els.previewModal.style.display = "none";
    previewOpen = false;
  }
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape") {
    els.previewModal.style.display = "none";
    previewOpen = false;
  }
});

// Live updates from the server (other clients / drift watcher).
function subscribeSockets() {
  state.slices.forEach((s) => {
    socket.on(`jenkins:${s.key}:config`, (cfg) => {
      state.configs[s.key] = cfg;
      if (s.key === state.active) renderForm(s.key);
    });
    socket.on(`jenkins:${s.key}:status`, (st) => {
      state.statuses[s.key] = st;
      renderTabs();
      if (s.key === state.active) renderDrift();
    });
  });
}

async function init() {
  setSaveState("idle");
  try {
    const meta = await api("/api/cicd/jenkins/slices");
    state.slices = meta.slices || [];
    subscribeSockets();
    await Promise.all(
      state.slices.map(async (s) => {
        const data = await api(`/api/cicd/jenkins/${s.key}/config`);
        state.configs[s.key] = data.config;
        state.statuses[s.key] = data.status;
      })
    );
    if (state.slices.length) activate(state.slices[0].key);
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
