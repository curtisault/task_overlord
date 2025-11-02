const TimeUntil = {
  mounted() {
    setInterval(() => {
      this.do_update();
    }, 1000);

    this.do_update();
  },

  updated() {
    this.do_update();
  },

  do_update() {
    until = new Date(this.el.dataset.until).getTime();
    prefix = this.el.dataset.prefix || "";
    precision = this.el.dataset.precision || "second";

    let time = Math.max(Math.floor((until - new Date().getTime()) / 1000), 0);

    const days = Math.floor(time / (60 * 60 * 24));
    time -= days * 60 * 60 * 24;
    const hours = Math.floor(time / (60 * 60));
    time -= hours * 60 * 60;
    const minutes = Math.floor(time / 60);
    time -= minutes * 60;
    const seconds = Math.floor(time % 60);

    let text = "";

    if (days > 0) {
      text = `${prefix}${days}d ${hours}h`;
    } else if (hours > 0) {
      text = `${prefix}${hours}h ${minutes}m`;
    } else if (precision == "minute") {
      text = `${prefix}${minutes}m`;
    } else {
      if (minutes > 0) {
        text = `${prefix}${minutes}m ${seconds}s`;
      } else if (seconds > 0) {
        text = `${prefix}${seconds}s`;
      } else {
        text = `expired`;
      }
    }

    this.el.innerHTML = `${text}`;
  },
};

export { TimeUntil };
