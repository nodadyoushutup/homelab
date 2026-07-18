"use strict";

const socket = io();

const els = {
  rows: document.getElementById("node-rows"),
  empty: document.getElementById("empty-state"),
  yaml: document.getElementById("yaml-preview"),
  form: document.getElementById("node-form"),
  id: document.getElementById("f-id"),
  name: document.getElementById("f-name"),
  host: document.getElementById("f-host"),
  user: document.getElementById("f-user"),
  role: document.getElementById("f-role"),
  port: document.getElementById("f-port"),
  labels: document.getElementById("f-labels"),
  formTitle: document.getElementById("form-title"),
  saveBtn: document.getElementById("save-btn"),
  cancelEdit: document.getElementById("cancel-edit"),
  applyBtn: document.getElementById("apply-btn"),
  status: document.getElementById("connection-status"),
};

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({
        "&": "&amp;",
        "<": "&lt;",
        ">": "&gt;",
        '"': "&quot;",
        "'": "&#39;",
      }[ch])
  );
}

function labelsToString(labels) {
  return Object.entries(labels || {})
    .map(([key, value]) => `${key}=${value}`)
    .join(", ");
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
      : `<span class="text-xs text-slate-600">—</span>`;
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3">
        <div class="font-medium text-slate-100">${escapeHtml(node.name)}</div>
        <div class="text-xs text-slate-500">${escapeHtml(node.host)}</div>
      </td>
      <td class="px-4 py-3">${roleBadge(node.role)}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-400">${escapeHtml(
        node.ssh_user
      )}@${escapeHtml(node.host)}:${escapeHtml(node.ssh_port)}</td>
      <td class="px-4 py-3">${labelHtml}</td>
      <td class="px-4 py-3 text-right whitespace-nowrap">
        <button data-edit="${node.id}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="Edit">
          <i class="fa-solid fa-pen"></i>
        </button>
        <button data-delete="${node.id}" data-name="${escapeHtml(
          node.name
        )}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete">
          <i class="fa-solid fa-trash"></i>
        </button>
      </td>`;
    els.rows.appendChild(row);
  });

  currentNodes = nodes;
}

let currentNodes = [];

function renderYaml(text) {
  els.yaml.textContent = text || "";
}

function resetForm() {
  els.id.value = "";
  els.form.reset();
  els.port.value = "22";
  els.role.value = "worker";
  els.formTitle.textContent = "Add node";
  els.saveBtn.innerHTML = '<i class="fa-solid fa-plus mr-2"></i>Add node';
  els.cancelEdit.hidden = true;
}

function startEdit(node) {
  els.id.value = node.id;
  els.name.value = node.name;
  els.host.value = node.host;
  els.user.value = node.ssh_user;
  els.role.value = node.role;
  els.port.value = node.ssh_port;
  els.labels.value = labelsToString(node.labels);
  els.formTitle.textContent = `Edit ${node.name}`;
  els.saveBtn.innerHTML = '<i class="fa-solid fa-check mr-2"></i>Save changes';
  els.cancelEdit.hidden = false;
  els.name.focus();
}

els.form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const payload = {
    name: els.name.value.trim(),
    host: els.host.value.trim(),
    ssh_user: els.user.value.trim(),
    role: els.role.value,
    ssh_port: parseInt(els.port.value, 10) || 22,
    labels: stringToLabels(els.labels.value),
  };
  const id = els.id.value;
  try {
    if (id) {
      await api(`/api/swarm/nodes/${id}`, {
        method: "PUT",
        body: JSON.stringify(payload),
      });
      toast(`Updated ${payload.name}`, "success");
    } else {
      await api("/api/swarm/nodes", {
        method: "POST",
        body: JSON.stringify(payload),
      });
      toast(`Added ${payload.name}`, "success");
    }
    resetForm();
  } catch (err) {
    toast(err.message, "error");
  }
});

els.cancelEdit.addEventListener("click", resetForm);

els.rows.addEventListener("click", async (event) => {
  const editBtn = event.target.closest("[data-edit]");
  if (editBtn) {
    const node = currentNodes.find(
      (n) => String(n.id) === editBtn.dataset.edit
    );
    if (node) startEdit(node);
    return;
  }
  const delBtn = event.target.closest("[data-delete]");
  if (delBtn) {
    if (!confirm(`Delete node "${delBtn.dataset.name}"?`)) return;
    try {
      await api(`/api/swarm/nodes/${delBtn.dataset.delete}`, {
        method: "DELETE",
      });
      toast(`Deleted ${delBtn.dataset.name}`, "success");
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

els.applyBtn.addEventListener("click", async () => {
  try {
    const result = await api("/api/swarm/apply", { method: "POST" });
    toast(`Wrote swarm.yaml (${result.count} nodes)`, "success");
  } catch (err) {
    toast(err.message, "error");
  }
});

socket.on("connect", () => {
  els.status.innerHTML =
    '<i class="fa-solid fa-circle mr-1 text-[8px] text-emerald-400"></i>connected';
});
socket.on("disconnect", () => {
  els.status.innerHTML =
    '<i class="fa-solid fa-circle mr-1 text-[8px] text-rose-400"></i>disconnected';
});
socket.on("swarm:nodes", renderNodes);
socket.on("config:written", (event) => renderYaml(event.yaml));

async function init() {
  try {
    const [nodes, yaml] = await Promise.all([
      api("/api/swarm/nodes"),
      api("/api/swarm/yaml"),
    ]);
    renderNodes(nodes);
    renderYaml(yaml.yaml);
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
