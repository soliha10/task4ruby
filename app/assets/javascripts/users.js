(() => {
  "use strict";

  const table = document.getElementById("users-table");
  if (!table) return;

  const STORAGE_KEY = "assistant-history";
  const STORED_TURNS = 40;
  const SENT_TURNS = 20;
  const RELOAD_DELAY_MS = 1200;
  const ERROR_CLASS = "is-error";

  const byId = (id) => document.getElementById(id);
  const tbody = table.querySelector("tbody");
  const selectAll = byId("select-all");
  const filterInput = byId("table-filter");
  const actionButtons = document.querySelectorAll(".bulk-action");
  const selectionInfo = byId("selection-info");
  const rowCount = byId("row-count");
  const emptyMessage = byId("empty-message");
  const chatForm = byId("chat-form");
  const chatInput = byId("chat-input");
  const chatSend = byId("chat-send");
  const chatMessages = byId("chat-messages");
  const chatHint = byId("chat-hint");
  const csrfToken = document.querySelector("meta[name='csrf-token']").content;

  let assistantFilterIds = null;

  const rows = () => Array.from(tbody.rows);
  const checkbox = (row) => row.querySelector(".row-check");
  const isChecked = (row) => checkbox(row).checked;
  const visibleRows = () => rows().filter((row) => !row.hidden);
  const idSet = (ids) => new Set(ids.map(String));

  document.querySelectorAll("[data-bs-toggle='tooltip']").forEach((element) => new bootstrap.Tooltip(element));

  const updateToolbar = () => {
    const visible = visibleRows();
    const checkedCount = rows().filter(isChecked).length;
    const visibleChecked = visible.filter(isChecked).length;

    actionButtons.forEach((button) => { button.disabled = checkedCount === 0; });
    selectionInfo.textContent = checkedCount ? `${checkedCount} selected` : "";
    selectAll.checked = visible.length > 0 && visibleChecked === visible.length;
    selectAll.indeterminate = visibleChecked > 0 && visibleChecked < visible.length;
    rowCount.textContent = `${visible.length} of ${rows().length} users shown`;
    emptyMessage.hidden = visible.length > 0;
  };

  const checkRows = (targetRows, isWanted) => {
    targetRows.forEach((row) => { checkbox(row).checked = isWanted(row); });
    updateToolbar();
  };

  const selectIds = (ids) => {
    const wanted = idSet(ids);
    checkRows(rows(), (row) => wanted.has(row.dataset.id));
  };

  const matchesQuery = (row, query) => !query || row.dataset.name.toLowerCase().includes(query) || row.dataset.email.includes(query);
  const matchesAssistant = (row) => !assistantFilterIds || assistantFilterIds.has(row.dataset.id);

  const applyFilters = () => {
    const query = filterInput.value.trim().toLowerCase();
    rows().forEach((row) => {
      row.hidden = !(matchesQuery(row, query) && matchesAssistant(row));
      if (row.hidden) checkbox(row).checked = false;
    });
    updateToolbar();
  };

  const setAssistantFilter = (ids) => {
    assistantFilterIds = ids && idSet(ids);
    if (!ids) filterInput.value = "";
    applyFilters();
  };

  const SORT_KEYS = {
    name: (row) => row.dataset.name.toLowerCase(),
    email: (row) => row.dataset.email,
    status: (row) => row.dataset.status,
    last_login_at: (row) => row.dataset.lastLogin
  };

  const compareWithEmptyLast = (first, second, factor) => {
    if (!first && second) return 1;
    if (first && !second) return -1;
    if (first === second) return 0;
    return first < second ? -factor : factor;
  };

  const sortRows = (field, dir) => {
    const key = SORT_KEYS[field];
    if (!key) return;
    const factor = dir === "asc" ? 1 : -1;
    rows()
      .sort((first, second) => compareWithEmptyLast(key(first), key(second), factor))
      .forEach((row) => tbody.appendChild(row));
  };

  const loadHistory = () => {
    try { return JSON.parse(sessionStorage.getItem(STORAGE_KEY)) || []; } catch { return []; }
  };

  const saveHistory = (turns) => {
    try {
      sessionStorage.setItem(STORAGE_KEY, JSON.stringify(turns.slice(-STORED_TURNS)));
      return true;
    } catch {
      return false;
    }
  };

  let history = loadHistory();

  const addMessage = (role, text, extraClass = "") => {
    const isUser = role === "user";
    chatHint.hidden = true;
    const wrapper = document.createElement("div");
    wrapper.className = `chat-row ${isUser ? "from-user" : "from-assistant"}`;
    const bubble = document.createElement("div");
    bubble.className = `chat-message ${extraClass}`;
    bubble.textContent = text;
    wrapper.appendChild(bubble);
    chatMessages.appendChild(wrapper);
    chatMessages.scrollTop = chatMessages.scrollHeight;
    return wrapper;
  };

  const ACTIONS = {
    select: (action) => selectIds(action.ids),
    clear_selection: () => selectIds([]),
    filter: (action) => setAssistantFilter(action.ids),
    clear_filter: () => setAssistantFilter(null),
    sort: (action) => sortRows(action.field, action.dir)
  };

  const runActions = (actions) => {
    actions.forEach((action) => ACTIONS[action.type]?.(action));
    if (actions.some((action) => action.type === "reload")) setTimeout(() => window.location.reload(), RELOAD_DELAY_MS);
  };

  const postMessage = (message) => fetch("/assistant", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": csrfToken },
    body: JSON.stringify({ message, history: history.slice(-SENT_TURNS) })
  });

  const showReply = (message, response, data) => {
    const reply = response.ok ? data.reply : (data.error || `Request failed (HTTP ${response.status}).`);
    addMessage("assistant", reply, response.ok && !data.error ? "" : ERROR_CLASS);
    history.push({ role: "user", text: message }, { role: "assistant", text: reply });
    saveHistory(history);
    runActions(data.actions || []);
  };

  const setBusy = (busy) => {
    chatSend.disabled = busy;
    if (!busy) chatInput.focus();
  };

  const sendMessage = async (event) => {
    event.preventDefault();
    const message = chatInput.value.trim();
    if (!message) return;

    addMessage("user", message);
    chatInput.value = "";
    setBusy(true);
    const thinking = addMessage("assistant", "Thinking…", "is-pending");

    try {
      const response = await postMessage(message);
      const data = await response.json().catch(() => ({}));
      if (response.status === 401) {
        window.location.href = data.redirect || "/login";
        return;
      }
      thinking.remove();
      showReply(message, response, data);
    } catch {
      thinking.remove();
      addMessage("assistant", "Network error. Please try again.", ERROR_CLASS);
    } finally {
      setBusy(false);
    }
  };

  const clearChat = () => {
    history = [];
    saveHistory(history);
    chatMessages.querySelectorAll(".chat-row").forEach((element) => element.remove());
    chatHint.hidden = false;
  };

  selectAll.addEventListener("change", () => checkRows(visibleRows(), () => selectAll.checked));
  tbody.addEventListener("change", (event) => {
    if (event.target.classList.contains("row-check")) updateToolbar();
  });
  filterInput.addEventListener("input", applyFilters);
  chatForm.addEventListener("submit", sendMessage);
  byId("chat-clear").addEventListener("click", clearChat);
  chatHint.addEventListener("click", (event) => {
    const chip = event.target.closest(".chat-chip");
    if (!chip) return;
    chatInput.value = chip.textContent.trim();
    chatForm.requestSubmit();
  });

  history.forEach((turn) => addMessage(turn.role, turn.text));
  updateToolbar();
})();
