/* Annotation layer for the parity gallery.
 * Hover a render to highlight it; click to drop a numbered pin and type feedback.
 * Feedback posts to the server (feedback.jsonl) so the agent reads it directly — no screenshots.
 */
(function () {
  "use strict";

  var feedback = [];

  // ---- side panel -------------------------------------------------------
  var panel = document.createElement("div");
  panel.id = "fbpanel";
  panel.innerHTML =
    '<div class="fbhead"><b>Feedback</b> <span id="fbcount">0</span>' +
    '<button id="fbclear" title="Clear all">clear all</button>' +
    '<button id="fbtoggle" title="Hide/show pins">hide pins</button></div>' +
    '<div class="fbhint">Click any render to pin feedback. Esc cancels.</div>' +
    '<div id="fblist"></div>';
  document.body.appendChild(panel);
  var listEl = panel.querySelector("#fblist");
  var countEl = panel.querySelector("#fbcount");
  var pinsVisible = true;

  panel.querySelector("#fbclear").onclick = function () {
    if (!confirm("Clear ALL feedback?")) return;
    fetch("/feedback/clear", { method: "POST" }).then(load);
  };
  panel.querySelector("#fbtoggle").onclick = function () {
    pinsVisible = !pinsVisible;
    document.body.classList.toggle("fbhide", !pinsVisible);
    panel.querySelector("#fbtoggle").textContent = pinsVisible ? "hide pins" : "show pins";
  };

  function targetOf(render) {
    return {
      widget: render.getAttribute("data-widget"),
      state: render.getAttribute("data-state"),
      platform: render.getAttribute("data-platform"),
    };
  }
  function labelFor(item) {
    return item.widget + "/" + item.state + " · " + item.platform;
  }

  // ---- render pins + list ----------------------------------------------
  function clearPins() {
    document.querySelectorAll(".fbpin").forEach(function (p) { p.remove(); });
  }
  function render() {
    clearPins();
    listEl.innerHTML = "";
    countEl.textContent = String(feedback.length);
    feedback.forEach(function (item, i) {
      // pin on the matching render
      var sel = '.render[data-widget="' + item.widget + '"][data-state="' + item.state + '"][data-platform="' + item.platform + '"]';
      var render = document.querySelector(sel);
      if (render && item.xPct != null) {
        var pin = document.createElement("div");
        pin.className = "fbpin";
        pin.style.left = item.xPct + "%";
        pin.style.top = item.yPct + "%";
        pin.textContent = String(i + 1);
        pin.title = item.note;
        render.appendChild(pin);
      }
      // list row
      var row = document.createElement("div");
      row.className = "fbrow";
      row.innerHTML = '<span class="fbnum"></span><span class="fbtgt"></span>' +
        '<span class="fbnote"></span><button class="fbdel" title="delete">×</button>';
      row.querySelector(".fbnum").textContent = String(i + 1);
      row.querySelector(".fbtgt").textContent = labelFor(item);
      row.querySelector(".fbnote").textContent = item.note;
      row.querySelector(".fbdel").onclick = function () {
        fetch("/feedback/delete", { method: "POST", body: JSON.stringify({ index: i }) }).then(load);
      };
      row.onmouseenter = function () {
        var r = document.querySelector(sel);
        if (r) r.classList.add("fbflash");
      };
      row.onmouseleave = function () {
        var r = document.querySelector(sel);
        if (r) r.classList.remove("fbflash");
      };
      listEl.appendChild(row);
    });
  }
  function load() {
    return fetch("/feedback").then(function (r) { return r.json(); }).then(function (items) {
      feedback = items;
      render();
    }).catch(function () {});
  }

  // ---- click to annotate ------------------------------------------------
  var composing = null;
  function closeComposer() {
    if (composing) { composing.remove(); composing = null; }
  }
  document.addEventListener("keydown", function (e) { if (e.key === "Escape") closeComposer(); });

  function openComposer(render, xPct, yPct) {
    closeComposer();
    var tgt = targetOf(render);
    var box = document.createElement("div");
    box.className = "fbcompose";
    box.style.left = xPct + "%";
    box.style.top = yPct + "%";
    box.innerHTML = '<div class="fbwhere"></div>' +
      '<textarea rows="2" placeholder="What should change here?"></textarea>' +
      '<div class="fbbtns"><button class="fbsave">save</button><button class="fbcancel">cancel</button></div>';
    box.querySelector(".fbwhere").textContent = tgt.widget + "/" + tgt.state + " · " + tgt.platform;
    render.appendChild(box);
    composing = box;
    var ta = box.querySelector("textarea");
    ta.focus();
    box.querySelector(".fbcancel").onclick = closeComposer;
    function save() {
      var note = ta.value.trim();
      if (!note) { closeComposer(); return; }
      var item = { widget: tgt.widget, state: tgt.state, platform: tgt.platform, xPct: Math.round(xPct), yPct: Math.round(yPct), note: note };
      fetch("/feedback", { method: "POST", body: JSON.stringify(item) }).then(load);
      closeComposer();
    }
    box.querySelector(".fbsave").onclick = save;
    ta.addEventListener("keydown", function (e) {
      if (e.key === "Enter" && (e.metaKey || e.ctrlKey)) { e.preventDefault(); save(); }
    });
  }

  document.querySelectorAll(".render").forEach(function (render) {
    render.addEventListener("click", function (e) {
      if (e.target.closest(".fbcompose") || e.target.closest(".fbpin")) return;
      var rect = render.getBoundingClientRect();
      var xPct = ((e.clientX - rect.left) / rect.width) * 100;
      var yPct = ((e.clientY - rect.top) / rect.height) * 100;
      openComposer(render, Math.max(0, Math.min(100, xPct)), Math.max(0, Math.min(100, yPct)));
    });
  });

  load();
  setInterval(load, 4000); // pick up deletes/edits made elsewhere
})();
