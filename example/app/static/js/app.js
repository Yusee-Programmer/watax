// watax-notes — progressive-enhancement script.
// The app works fully via plain HTML form posts; this adds a delete
// confirmation, plus live demos of the Server-Sent Events and WebSocket
// endpoints (which can't be shown by opening the URLs directly in a browser).
document.addEventListener("DOMContentLoaded", function () {
    // --- Delete confirmation -------------------------------------------------
    var deleteForms = document.querySelectorAll(".note-delete");
    for (var i = 0; i < deleteForms.length; i++) {
        deleteForms[i].addEventListener("submit", function (e) {
            if (!window.confirm("Delete this note?")) {
                e.preventDefault();
            }
        });
    }

    function log(el, line) {
        if (!el) return;
        if (el.textContent.indexOf("(") === 0) el.textContent = "";
        el.textContent += line + "\n";
        el.scrollTop = el.scrollHeight;
    }

    // --- Server-Sent Events (/events) ---------------------------------------
    var sseLog = document.getElementById("sse-log");
    var sseBtn = document.getElementById("sse-start");
    if (sseBtn && window.EventSource) {
        sseBtn.addEventListener("click", function () {
            sseLog.textContent = "";
            log(sseLog, "connecting to /events ...");
            var es = new EventSource("/events");
            es.onmessage = function (ev) { log(sseLog, "event: " + ev.data); };
            es.onerror = function () { log(sseLog, "(stream closed)"); es.close(); };
        });
    } else if (sseBtn) {
        sseBtn.disabled = true;
    }

    // --- WebSocket (/ws) -----------------------------------------------------
    var wsLog = document.getElementById("ws-log");
    var wsForm = document.getElementById("ws-form");
    var wsInput = document.getElementById("ws-input");
    if (wsForm && window.WebSocket) {
        var proto = location.protocol === "https:" ? "wss:" : "ws:";
        var ws = new WebSocket(proto + "//" + location.host + "/ws");
        ws.onopen = function () { log(wsLog, "(connected)"); };
        ws.onmessage = function (ev) { log(wsLog, "<- " + ev.data); };
        ws.onclose = function () { log(wsLog, "(disconnected)"); };
        wsForm.addEventListener("submit", function (e) {
            e.preventDefault();
            var msg = wsInput.value;
            if (msg && ws.readyState === WebSocket.OPEN) {
                ws.send(msg);
                log(wsLog, "-> " + msg);
                wsInput.value = "";
            }
        });
    } else if (wsForm) {
        wsForm.style.display = "none";
    }
});
