"use strict";

const socket = io();

const els = {
  sets: document.getElementById("sets"),
  setsEmpty: document.getElementById("sets-empty"),
  sharedRows: document.getElementById("shared-rows"),
  sharedEmpty: document.getElementById("shared-empty"),
  hostHint: document.getElementById("host-hint"),
  hostFiles: document.getElementById("host-files"),
  newSetBtn: document.getElementById("new-set-btn"),
  modalNewset: document.getElementById("modal-newset"),
  newsetForm: document.getElementById("newset-form"),
  newsetName: document.getElementById("newset-name"),
  modalUpload: document.getElementById("modal-upload"),
  uploadForm: document.getElementById("upload-form"),
  uploadSet: document.getElementById("upload-set"),
  uploadName: document.getElementById("upload-name"),
  uploadFile: document.getElementById("upload-file"),
  modalView: document.getElementById("modal-view"),
  viewTitle: document.getElementById("view-title"),
  viewBody: document.getElementById("view-body"),
  modalAuthkeys: document.getElementById("modal-authkeys"),
  authkeysForm: document.getElementById("authkeys-form"),
  authkeysSet: document.getElementById("authkeys-set"),
  authkeysBody: document.getElementById("authkeys-body"),
};

function escapeHtml(value) {
  return String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch])
  );
}

function humanSize(bytes) {
  if (bytes < 1024) return `${bytes} B`;
  return `${(bytes / 1024).toFixed(1)} KB`;
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
  el.className = `pointer-events-auto rounded-lg border px-4 py-2 text-sm shadow-lg ${
    palette[kind] || palette.info
  }`;
  el.textContent = message;
  document.getElementById("toast-root").appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity 300ms";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 300);
  }, 2800);
}

function kindBadge(kind) {
  const map = {
    private_key: ["fa-lock", "bg-amber-500/15 text-amber-300 border-amber-500/40", "private key"],
    public_key: ["fa-key", "bg-emerald-500/15 text-emerald-300 border-emerald-500/40", "public key"],
    certificate: ["fa-certificate", "bg-sky-500/15 text-sky-300 border-sky-500/40", "certificate"],
    config: ["fa-gear", "bg-slate-700/40 text-slate-300 border-slate-600/50", "config"],
    known_hosts: ["fa-list", "bg-slate-700/40 text-slate-300 border-slate-600/50", "known_hosts"],
    authorized_keys: ["fa-user-check", "bg-indigo-500/15 text-indigo-300 border-indigo-500/40", "authorized_keys"],
  };
  const [icon, cls, label] = map[kind] || ["fa-file", "bg-slate-700/40 text-slate-300 border-slate-600/50", kind];
  return `<span class="inline-flex items-center gap-1.5 rounded-full border px-2.5 py-0.5 text-xs font-medium ${cls}"><i class="fa-solid ${icon}"></i>${escapeHtml(label)}</span>`;
}

function fileActions(setName, file) {
  const view = file.sensitive
    ? ""
    : `<button data-view="${escapeHtml(file.name)}" data-set="${escapeHtml(setName)}" class="mr-1 rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-sky-300" title="View"><i class="fa-solid fa-eye"></i></button>`;
  return `${view}<button data-delfile="${escapeHtml(file.name)}" data-set="${escapeHtml(setName)}" class="rounded-md px-2 py-1 text-slate-400 hover:bg-slate-700 hover:text-rose-300" title="Delete"><i class="fa-solid fa-trash"></i></button>`;
}

function renderSets(sets) {
  els.sets.innerHTML = "";
  els.setsEmpty.hidden = sets.length > 0;
  sets.forEach((set) => {
    const files = set.files
      .map(
        (f) => `
        <tr class="hover:bg-slate-800/40">
          <td class="px-3 py-2 font-mono text-xs text-slate-200">${escapeHtml(f.name)}</td>
          <td class="px-3 py-2">${kindBadge(f.kind)}</td>
          <td class="px-3 py-2 font-mono text-xs text-slate-500">${escapeHtml(f.octal)}</td>
          <td class="px-3 py-2 text-xs text-slate-500">${humanSize(f.size)}</td>
          <td class="px-3 py-2 text-right whitespace-nowrap">${fileActions(set.name, f)}</td>
        </tr>`
      )
      .join("");
    const fpr = set.fingerprint
      ? `<span class="font-mono text-xs text-slate-500">${escapeHtml(set.fingerprint)}</span>`
      : `<span class="text-xs text-slate-600">no public key</span>`;
    const card = document.createElement("div");
    card.className = "rounded-xl border border-slate-800 bg-slate-900/50 p-5";
    card.innerHTML = `
      <div class="mb-4 flex items-start justify-between gap-3">
        <div>
          <h3 class="flex items-center gap-2 text-base font-semibold text-slate-100">
            <i class="fa-solid fa-folder text-sky-400"></i>${escapeHtml(set.name)}
          </h3>
          <div class="mt-1">${fpr}</div>
        </div>
        <button data-delset="${escapeHtml(set.name)}" class="rounded-md px-2 py-1 text-xs text-slate-400 hover:bg-slate-800 hover:text-rose-300" title="Delete set">
          <i class="fa-solid fa-trash mr-1"></i>Delete set
        </button>
      </div>
      <div class="overflow-hidden rounded-lg border border-slate-800">
        <table class="w-full text-left">
          <tbody class="divide-y divide-slate-800">
            ${files || `<tr><td class="px-3 py-4 text-center text-xs text-slate-500" colspan="5">No files yet — sync or upload a key.</td></tr>`}
          </tbody>
        </table>
      </div>
      <div class="mt-4 flex flex-wrap gap-2">
        <button data-sync="${escapeHtml(set.name)}" class="rounded-lg border border-slate-700 px-3 py-1.5 text-sm text-slate-300 hover:bg-slate-800">
          <i class="fa-solid fa-download mr-1.5"></i>Sync from host
        </button>
        <button data-upload="${escapeHtml(set.name)}" class="rounded-lg border border-slate-700 px-3 py-1.5 text-sm text-slate-300 hover:bg-slate-800">
          <i class="fa-solid fa-upload mr-1.5"></i>Upload key
        </button>
        <button data-authkeys="${escapeHtml(set.name)}" class="rounded-lg border border-slate-700 px-3 py-1.5 text-sm text-slate-300 hover:bg-slate-800">
          <i class="fa-solid fa-user-check mr-1.5"></i>authorized_keys
        </button>
      </div>`;
    els.sets.appendChild(card);
  });
}

function renderShared(shared) {
  els.sharedRows.innerHTML = "";
  els.sharedEmpty.hidden = shared.length > 0;
  shared.forEach((f) => {
    const row = document.createElement("tr");
    row.className = "hover:bg-slate-800/40";
    row.innerHTML = `
      <td class="px-4 py-3 font-mono text-xs text-slate-200">${escapeHtml(f.name)}</td>
      <td class="px-4 py-3">${kindBadge(f.kind)}</td>
      <td class="px-4 py-3 font-mono text-xs text-slate-500">${escapeHtml(f.octal)}</td>
      <td class="px-4 py-3 text-xs text-slate-500">${humanSize(f.size)}</td>
      <td class="px-4 py-3 text-right text-xs text-slate-600">&mdash;</td>`;
    els.sharedRows.appendChild(row);
  });
}

function renderHost(host) {
  if (!host || !host.length) {
    els.hostHint.hidden = true;
    return;
  }
  els.hostFiles.textContent = host.map((f) => f.name).join(", ");
  els.hostHint.hidden = false;
}

function render(snapshot) {
  renderSets(snapshot.sets || []);
  renderShared(snapshot.shared || []);
  renderHost(snapshot.host || []);
}

// -- modals -------------------------------------------------------------------

function openModal(modal) {
  modal.style.display = "flex";
}
function closeModal(modal) {
  modal.style.display = "none";
}

document.querySelectorAll("[data-close]").forEach((btn) => {
  btn.addEventListener("click", () => closeModal(btn.closest("[id^='modal-']")));
});
document.querySelectorAll("[id^='modal-']").forEach((modal) => {
  modal.addEventListener("click", (e) => {
    if (e.target === modal) closeModal(modal);
  });
});

els.newSetBtn.addEventListener("click", () => {
  els.newsetName.value = "";
  openModal(els.modalNewset);
  els.newsetName.focus();
});

els.newsetForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    await api("/api/ssh/sets", {
      method: "POST",
      body: JSON.stringify({ name: els.newsetName.value.trim() }),
    });
    toast(`Created key set ${els.newsetName.value.trim()}`, "success");
    closeModal(els.modalNewset);
  } catch (err) {
    toast(err.message, "error");
  }
});

els.uploadForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const setName = els.uploadSet.textContent;
  const kind = els.uploadForm.querySelector("input[name='kind']:checked").value;
  const file = els.uploadFile.files[0];
  if (!file) return toast("Choose a file to upload", "error");
  const form = new FormData();
  form.append("file", file);
  form.append("kind", kind);
  form.append("name", els.uploadName.value.trim());
  try {
    const response = await fetch(`/api/ssh/sets/${encodeURIComponent(setName)}/upload`, {
      method: "POST",
      body: form,
    });
    const data = await response.json().catch(() => ({}));
    if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
    toast(`Uploaded ${data.name} to ${setName}`, "success");
    closeModal(els.modalUpload);
  } catch (err) {
    toast(err.message, "error");
  }
});

// prefill filename default based on chosen kind
els.uploadForm.addEventListener("change", (e) => {
  if (e.target.name === "kind") {
    els.uploadName.value = e.target.value === "public" ? "id_ed25519.pub" : "id_ed25519";
  }
});

// -- delegated actions on set cards ------------------------------------------

els.sets.addEventListener("click", async (e) => {
  const del = e.target.closest("[data-delset]");
  if (del) {
    const name = del.dataset.delset;
    if (!confirm(`Delete key set "${name}" and all its files?`)) return;
    try {
      await api(`/api/ssh/sets/${encodeURIComponent(name)}`, { method: "DELETE" });
      toast(`Deleted set ${name}`, "success");
    } catch (err) {
      toast(err.message, "error");
    }
    return;
  }

  const sync = e.target.closest("[data-sync]");
  if (sync) {
    const name = sync.dataset.sync;
    if (!confirm(`Sync the host ~/.ssh key pair into set "${name}"? Existing files with the same name will be overwritten.`)) return;
    try {
      const data = await api(`/api/ssh/sets/${encodeURIComponent(name)}/sync`, { method: "POST" });
      toast(`Synced ${data.copied.length} file(s) into ${name}`, "success");
    } catch (err) {
      toast(err.message, "error");
    }
    return;
  }

  const upload = e.target.closest("[data-upload]");
  if (upload) {
    els.uploadSet.textContent = upload.dataset.upload;
    els.uploadForm.reset();
    els.uploadName.value = "id_ed25519";
    openModal(els.modalUpload);
    return;
  }

  const authkeys = e.target.closest("[data-authkeys]");
  if (authkeys) {
    await openAuthkeys(authkeys.dataset.authkeys);
    return;
  }

  const view = e.target.closest("[data-view]");
  if (view) {
    await showFile(view.dataset.set, view.dataset.view);
    return;
  }

  const delfile = e.target.closest("[data-delfile]");
  if (delfile) {
    const { set, delfile: name } = delfile.dataset;
    if (!confirm(`Delete "${name}" from set "${set}"?`)) return;
    try {
      await api(`/api/ssh/sets/${encodeURIComponent(set)}/files/${encodeURIComponent(name)}`, { method: "DELETE" });
      toast(`Deleted ${name}`, "success");
    } catch (err) {
      toast(err.message, "error");
    }
  }
});

async function openAuthkeys(setName) {
  els.authkeysSet.textContent = setName;
  els.authkeysBody.value = "";
  try {
    const data = await api(
      `/api/ssh/sets/${encodeURIComponent(setName)}/files/authorized_keys`
    );
    els.authkeysBody.value = data.content || "";
  } catch (err) {
    // No authorized_keys yet — start from an empty editor.
  }
  openModal(els.modalAuthkeys);
  els.authkeysBody.focus();
}

els.authkeysForm.addEventListener("submit", async (e) => {
  e.preventDefault();
  const setName = els.authkeysSet.textContent;
  try {
    await api(`/api/ssh/sets/${encodeURIComponent(setName)}/authorized_keys`, {
      method: "PUT",
      body: JSON.stringify({ content: els.authkeysBody.value }),
    });
    toast(`Saved authorized_keys for ${setName}`, "success");
    closeModal(els.modalAuthkeys);
  } catch (err) {
    toast(err.message, "error");
  }
});

async function showFile(setName, name) {
  try {
    const data = await api(`/api/ssh/sets/${encodeURIComponent(setName)}/files/${encodeURIComponent(name)}`);
    els.viewTitle.textContent = `${setName}/${name}`;
    els.viewBody.textContent = data.content;
    openModal(els.modalView);
  } catch (err) {
    toast(err.message, "error");
  }
}

// -- socket + init ------------------------------------------------------------

socket.on("ssh:sets", render);

async function init() {
  try {
    render(await api("/api/ssh/sets"));
  } catch (err) {
    toast(err.message, "error");
  }
}

init();
