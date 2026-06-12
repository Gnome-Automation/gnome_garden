// assets/js/hooks/inactivity_logout.js

const InactivityLogout = {
  mounted() {
    this.timeoutMinutes = parseInt(this.el.dataset.timeout || "30", 10);

    // 0 = disabled
    if (this.timeoutMinutes === 0) return;

    this.timeoutMs = this.timeoutMinutes * 60 * 1000;
    this.warningMs = this.timeoutMs - 60_000; // show warning 60s before logout
    this.warningTimer = null;
    this.logoutTimer = null;
    this.warningShown = false;

    this._boundReset = this.resetTimer.bind(this);
    ["mousemove", "keydown", "touchstart", "click"].forEach((ev) =>
      document.addEventListener(ev, this._boundReset, { passive: true })
    );

    this.startTimers();
  },

  destroyed() {
    this.clearTimers();
    ["mousemove", "keydown", "touchstart", "click"].forEach((ev) =>
      document.removeEventListener(ev, this._boundReset)
    );
  },

  startTimers() {
    this.clearTimers();

    if (this.warningMs > 0) {
      this.warningTimer = setTimeout(() => {
        this.warningShown = true;
        this.pushEvent("show_inactivity_warning", { seconds_left: 60 });
        this.startCountdown();
      }, this.warningMs);
    } else {
      // timeout <= 60s — go straight to logout
      this.logoutTimer = setTimeout(() => {
        this.pushEvent("inactivity_logout", {});
      }, this.timeoutMs);
    }
  },

  startCountdown() {
    let secondsLeft = 60;
    this.countdownInterval = setInterval(() => {
      secondsLeft -= 1;
      this.pushEvent("inactivity_countdown", { seconds_left: secondsLeft });
      if (secondsLeft <= 0) {
        clearInterval(this.countdownInterval);
        this.pushEvent("inactivity_logout", {});
      }
    }, 1000);
  },

  clearTimers() {
    clearTimeout(this.warningTimer);
    clearTimeout(this.logoutTimer);
    clearInterval(this.countdownInterval);
    this.warningTimer = null;
    this.logoutTimer = null;
    this.countdownInterval = null;
    this.warningShown = false;
  },

  resetTimer() {
    if (this.warningShown) return; // don't reset once warning is up — user must click button
    this.startTimers();
  },
};

export default InactivityLogout;
