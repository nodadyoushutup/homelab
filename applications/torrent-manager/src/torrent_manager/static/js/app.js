(function () {
  "use strict";

  function autoDismissFlashes() {
    document.querySelectorAll("[data-flash]").forEach(function (node) {
      window.setTimeout(function () {
        node.style.opacity = "0";
        window.setTimeout(function () {
          node.remove();
        }, 250);
      }, 5000);
    });
  }

  function bindDeleteConfirmations() {
    document.querySelectorAll("[data-confirm-delete]").forEach(function (form) {
      form.addEventListener("submit", function (event) {
        var message =
          form.getAttribute("data-confirm-message") || "Delete this torrent record?";
        if (!window.confirm(message)) {
          event.preventDefault();
        }
      });
    });
  }

  function bindRowLinks() {
    document.querySelectorAll("[data-href]").forEach(function (row) {
      row.addEventListener("click", function (event) {
        if (event.target.closest("a, button, input, select, textarea, form, label")) {
          return;
        }
        var href = row.getAttribute("data-href");
        if (href) {
          window.location.href = href;
        }
      });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    autoDismissFlashes();
    bindDeleteConfirmations();
    bindRowLinks();
  });
})();
