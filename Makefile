.PHONY: test install-user uninstall-user

PREFIX ?= $(HOME)/.local
UNITDIR ?= $(HOME)/.config/systemd/user

test:
	python3 -m unittest discover -s tests -v

# Install the collector this machine already runs. Does not touch the
# sd.agents plugin clone — that stays in ~/.config/omarchy/plugins.
install-user:
	install -Dm755 bin/omarchy-agent-usage-grok $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok
	mkdir -p $(PREFIX)/bin
	ln -sfn $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok $(PREFIX)/bin/omarchy-agent-usage-grok
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.service $(UNITDIR)/omarchy-agent-usage-grok.service
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.timer $(UNITDIR)/omarchy-agent-usage-grok.timer
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.path $(UNITDIR)/omarchy-agent-usage-grok.path
	systemctl --user daemon-reload

uninstall-user:
	systemctl --user disable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path || true
	rm -f $(PREFIX)/bin/omarchy-agent-usage-grok
	rm -f $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.service
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.timer
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.path
	systemctl --user daemon-reload
