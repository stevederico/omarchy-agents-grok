.PHONY: test install-user uninstall-user

PREFIX ?= $(HOME)/.local
UNITDIR ?= $(HOME)/.config/systemd/user
PLUGINDIR ?= $(HOME)/.config/omarchy/plugins
HOOKDIR ?= $(HOME)/.config/omarchy/hooks/post-boot.d

test:
	python3 -m unittest discover -s tests -v
	bash tests/test_scanner.sh

install-user:
	install -Dm755 bin/omarchy-agent-usage-grok $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok
	mkdir -p $(PREFIX)/bin
	ln -sfn $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok $(PREFIX)/bin/omarchy-agent-usage-grok
	rm -rf $(PLUGINDIR)/sd.agents
	ln -sfn $(CURDIR)/plugin/sd.agents $(PLUGINDIR)/sd.agents
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.service $(UNITDIR)/omarchy-agent-usage-grok.service
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.timer $(UNITDIR)/omarchy-agent-usage-grok.timer
	install -Dm644 extras/systemd/omarchy-agent-usage-grok.path $(UNITDIR)/omarchy-agent-usage-grok.path
	install -Dm755 extras/hooks/omarchy-grok-usage.hook $(HOOKDIR)/omarchy-grok-usage.hook
	systemctl --user daemon-reload
	@echo "Enable with: systemctl --user enable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path"

uninstall-user:
	systemctl --user disable --now omarchy-agent-usage-grok.timer omarchy-agent-usage-grok.path || true
	rm -f $(PREFIX)/bin/omarchy-agent-usage-grok
	rm -f $(PREFIX)/lib/omarchy/omarchy-agent-usage-grok
	rm -rf $(PLUGINDIR)/sd.agents
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.service
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.timer
	rm -f $(UNITDIR)/omarchy-agent-usage-grok.path
	rm -f $(HOOKDIR)/omarchy-grok-usage.hook
	systemctl --user daemon-reload
