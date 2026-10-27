/* RetailPulse - browser-side helpers
   1. Keeps the user's store catalogue in this browser (localStorage), so it survives
      server restarts. Nothing is sent anywhere except to this app's own R session.
   2. Generic click handler: any element with data-rp-input="<shiny input id>" sends
      {value, n} to Shiny when clicked or activated with Enter/Space.
   3. Smooth scroll requests from the server. */
(function () {
  "use strict";
  var KEY = "retailpulse.catalogue.v1";

  function storageOk() {
    try { var t = "__rp_test__"; window.localStorage.setItem(t, t); window.localStorage.removeItem(t); return true; }
    catch (e) { return false; }
  }

  function sendStored() {
    var payload = { available: storageOk(), data: "" };
    if (payload.available) { try { payload.data = window.localStorage.getItem(KEY) || ""; } catch (e) { payload.available = false; } }
    payload.n = Date.now();
    Shiny.setInputValue("rp_catalogue", payload, { priority: "event" });
  }

  var handlersReady = false;
  $(document).on("shiny:connected", function () {
    sendStored();
    if (handlersReady) return;          // reconnects: handlers are already registered
    handlersReady = true;
    Shiny.addCustomMessageHandler("rp-catalogue-save", function (msg) {
      try { window.localStorage.setItem(KEY, msg.json); Shiny.setInputValue("rp_catalogue_saved", { ok: true, n: Date.now() }, { priority: "event" }); }
      catch (e) { Shiny.setInputValue("rp_catalogue_saved", { ok: false, error: String(e), n: Date.now() }, { priority: "event" }); }
    });
    Shiny.addCustomMessageHandler("rp-catalogue-clear", function (msg) {
      try { window.localStorage.removeItem(KEY); } catch (e) { /* storage unavailable */ }
    });
    Shiny.addCustomMessageHandler("rp-toggle", function (msg) {
      var el = document.getElementById(msg.id);
      if (el) el.style.display = msg.show ? "" : "none";
    });
    Shiny.addCustomMessageHandler("rp-scroll", function (msg) {
      var el = document.getElementById(msg.id);
      if (el) el.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  });

  function fire(el) {
    var id = el.getAttribute("data-rp-input");
    if (!id || !window.Shiny || !Shiny.setInputValue) return;
    Shiny.setInputValue(id, { value: el.getAttribute("data-rp-value") || "", n: Date.now() }, { priority: "event" });
  }
  $(document).on("click", "[data-rp-input]", function (e) { e.preventDefault(); e.stopPropagation(); fire(this); });
  $(document).on("keydown", "[data-rp-input]", function (e) {
    if (e.key === "Enter" || e.key === " ") { e.preventDefault(); fire(this); }
  });
})();
