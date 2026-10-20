---
name: Wi-Fi hardware compatibility
about: Scanning issues, missing networks, or hardware-specific problems
title: ''
labels: compatibility
assignees: ''
---

**What is not working?**
<!-- e.g. "No 6 GHz networks appear", "Scanning fails to start", "Only seeing 2.4 GHz" -->

**Your hardware**
- Mac model: <!-- e.g. MacBook Pro M3 (2024) -->
- macOS version: <!-- e.g. 15.4 -->
- Wi-Fi chipset: <!-- System Information → Network → Wi-Fi → Card Type -->
- Wi-Fi band(s) affected: <!-- 2.4 GHz / 5 GHz / 6 GHz -->

**Your Wi-Fi environment**
- Router / AP model and firmware version:
- Channel width in use: <!-- 20 / 40 / 80 / 160 MHz -->
- WPA version: <!-- WPA2 / WPA3 / WPA2+WPA3 mixed -->

**What have you already checked?**
- [ ] Wi-Fi is connected and working in macOS
- [ ] Other Wi-Fi scanners can see the expected networks
- [ ] Tried restarting WiFi Lens

**Logs**
WiFi Lens writes structured logs via OSLog. You can export them with:
`log show --predicate 'subsystem == "io.github.kaoru.wifi-lens"' --last 5m > wifi-lens.log`
Attach the log file if possible.
