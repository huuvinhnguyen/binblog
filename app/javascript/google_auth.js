const GOOGLE_SCRIPT_URL = "https://accounts.google.com/gsi/client";
let googleScriptPromise;
let googleAuthGeneration = 0;
let activeGoogleRequest;

function reconcileAfterNavigation(request) {
  // Fetch may have received a new Devise cookie; load the destination after it settles.
  const destination = request.navigationTarget;
  if (destination && window.location.href !== destination) {
    window.location.assign(destination);
  } else {
    window.location.reload();
  }
}

function markPageChange() {
  googleAuthGeneration += 1;
  if (activeGoogleRequest) activeGoogleRequest.needsRefresh = true;
}

function currentGoogleAuth(container, generation, intent) {
  return generation === googleAuthGeneration && container.isConnected && container.dataset.intent === intent;
}

function loadGoogleScript() {
  if (window.google?.accounts?.id) return Promise.resolve();
  if (googleScriptPromise) return googleScriptPromise;

  googleScriptPromise = new Promise((resolve, reject) => {
    let script = document.querySelector(`script[src="${GOOGLE_SCRIPT_URL}"]`);
    if (!script) {
      script = document.createElement("script");
      script.src = GOOGLE_SCRIPT_URL;
      script.async = true;
      script.defer = true;
      document.head.appendChild(script);
    }
    script.addEventListener("load", resolve, { once: true });
    script.addEventListener("error", reject, { once: true });
    if (window.google?.accounts?.id) resolve();
  });
  return googleScriptPromise;
}

function errorMessage(code) {
  const messages = {
    link_required: "Tài khoản chưa được liên kết. Hãy đăng nhập bằng mật khẩu rồi liên kết Google trong trang tài khoản.",
    identity_conflict: "Không thể liên kết tài khoản Google này. Hãy kiểm tra tài khoản Google hoặc thử tài khoản khác.",
    provider_already_linked: "Tài khoản đã liên kết với một tài khoản Google khác.",
    reauthentication_required: "Mật khẩu xác nhận không đúng. Hãy nhập lại và thử lần nữa.",
    invalid_provider_credential: "Thông tin Google không hợp lệ hoặc đã hết hạn. Hãy thử lại.",
    provider_unavailable: "Google tạm thời không khả dụng. Hãy thử lại sau.",
    email_verification_required: "Google không cung cấp email đã xác minh cho tài khoản này.",
    username_unavailable: "Không thể tạo tài khoản lúc này. Hãy thử lại sau."
  };
  return messages[code] || "Không thể hoàn tất. Hãy thử lại.";
}

async function submitCredential(container, response, generation, intent) {
  if (!currentGoogleAuth(container, generation, intent)) return;
  const status = container.querySelector("[data-google-auth-status]");
  if (container.dataset.pending === "true") return;
  if (activeGoogleRequest) {
    status.textContent = "Đang hoàn tất yêu cầu Google trước đó. Vui lòng đợi trang tải lại.";
    return;
  }
  const passwordField = document.querySelector("[data-google-current-password]");
  if (container.dataset.intent === "link" && !passwordField?.value) {
    status.textContent = "Nhập mật khẩu hiện tại trước khi liên kết Google.";
    passwordField?.focus();
    return;
  }
  container.dataset.pending = "true";
  container.setAttribute("aria-busy", "true");
  status.textContent = "Đang xác minh với Google…";

  const payload = new URLSearchParams({
    authenticity_token: document.querySelector('meta[name="csrf-token"]')?.content || "",
    credential: response.credential,
    intent: container.dataset.intent
  });
  if (container.dataset.intent === "link") {
    payload.set("current_password", passwordField.value);
  }

  const request = { needsRefresh: false, navigationTarget: null };
  const controller = new AbortController();
  activeGoogleRequest = request;
  const timeout = window.setTimeout(() => {
    // A response may already have set a cookie, so refresh even after an abort.
    request.needsRefresh = true;
    controller.abort();
  }, 30000);
  try {
    const result = await fetch("/auth/google", {
      method: "POST",
      signal: controller.signal,
      credentials: "same-origin",
      headers: {
        "Accept": "text/html",
        "Content-Type": "application/x-www-form-urlencoded;charset=UTF-8",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
      },
      body: payload.toString()
    });
    const body = await result.json();
    if (request.needsRefresh || !currentGoogleAuth(container, generation, intent)) {
      request.needsRefresh = true;
      return;
    }
    if (!result.ok) throw new Error(body.code || "request_failed");

    if (intent === "link") {
      status.textContent = body.code === "already_linked" ? "Google đã được liên kết." : "Google đã được liên kết thành công.";
      window.setTimeout(() => {
        if (currentGoogleAuth(container, generation, intent)) window.location.reload();
      }, 700);
    } else {
      window.location.assign(body.redirect_url || "/");
    }
  } catch (error) {
    if (request.needsRefresh || !currentGoogleAuth(container, generation, intent)) {
      request.needsRefresh = true;
      return;
    }
    if (intent === "link" && error.message === "authentication_required") {
      status.textContent = "Phiên đăng nhập đã hết hạn. Vui lòng đăng nhập lại.";
      const signInLink = document.createElement("a");
      signInLink.href = container.dataset.signInUrl;
      signInLink.textContent = "Đăng nhập lại";
      status.append(" ", signInLink);
      container.querySelector("[data-google-button]")?.replaceChildren();
    } else {
      status.textContent = errorMessage(error.message);
    }
    container.dataset.pending = "false";
    container.removeAttribute("aria-busy");
  } finally {
    window.clearTimeout(timeout);
    if (activeGoogleRequest === request) activeGoogleRequest = null;
    if (request.needsRefresh) reconcileAfterNavigation(request);
  }
}

function initializeGoogleAuth() {
  document.querySelectorAll("[data-google-auth]").forEach((container) => {
    const button = container.querySelector("[data-google-button]");
    if (!button || button.dataset.initialized === "true") return;
    button.dataset.initialized = "true";
    const generation = googleAuthGeneration;
    const intent = container.dataset.intent;

    loadGoogleScript().then(() => {
      if (!currentGoogleAuth(container, generation, intent)) return;
      window.google.accounts.id.initialize({
        client_id: container.dataset.clientId,
        ux_mode: "popup",
        callback: (response) => submitCredential(container, response, generation, intent)
      });
      window.google.accounts.id.renderButton(button, {
        type: "standard",
        theme: "outline",
        size: "large",
        text: intent === "link" ? "continue_with" :
          (intent === "sign_up" ? "signup_with" : "signin_with"),
        shape: "rectangular"
      });
    }).catch(() => {
      if (!currentGoogleAuth(container, generation, intent)) return;
      googleScriptPromise = null;
      document.querySelector(`script[src="${GOOGLE_SCRIPT_URL}"]`)?.remove();
      const status = container.querySelector("[data-google-auth-status]");
      status.textContent = "Không tải được Google. Kiểm tra kết nối rồi thử lại.";
      button.replaceChildren();
      const retry = document.createElement("button");
      retry.type = "button";
      retry.className = "btn btn-outline-primary";
      retry.textContent = "Thử tải Google lại";
      retry.addEventListener("click", () => {
        button.dataset.initialized = "false";
        initializeGoogleAuth();
      }, { once: true });
      button.appendChild(retry);
    });
  });
}

document.addEventListener("turbo:visit", (event) => {
  markPageChange();
  if (activeGoogleRequest) {
    activeGoogleRequest.navigationTarget = event.detail.url;
  }
});

document.addEventListener("turbo:before-render", markPageChange);

document.addEventListener("turbo:before-cache", () => {
  markPageChange();
  document.querySelectorAll("[data-google-auth]").forEach((container) => {
    const button = container.querySelector("[data-google-button]");
    if (button) {
      button.dataset.initialized = "false";
      button.replaceChildren();
    }
    container.dataset.pending = "false";
    container.removeAttribute("aria-busy");
  });
});

document.addEventListener("turbo:load", initializeGoogleAuth);
document.addEventListener("DOMContentLoaded", initializeGoogleAuth);
