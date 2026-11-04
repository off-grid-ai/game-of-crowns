---
name: goc-tests
description: How Game of Crowns changes are proven to work. There is no unit suite yet; proof is bridge calls, compile checks and renders. Load before claiming any change works.
---

# Proving it works

1. **Behaviour, seen.** A change is done when it's seen working: a bridge reply, a render, a log line. A compile pass is not proof.
2. **Bridge first.** Hit the endpoint with `curl` (harmless input first: a bad id, then a real one). Check the realm's state through the bridge's own read endpoints, not by opening JSON files.
3. **Seed through the product.** Make test state the way the game does: create a chronicle, edit a character, answer a petition via the bridge. Never hand-edit `bridge/chronicles/*/state`.
4. **Renders for anything visible.** Use the screenshot flags (see `goc-run`) and look at every image yourself before calling it done.
5. **Probe, don't guess.** When something's wrong, add a temporary `# DEBUG-PROBE` print, measure, fix the cause, then strip the probes.
6. **Throwaway realms for risky tests.** Create a test chronicle, then reopen Ali's realm and delete the test one.
7. **A failure is a finding.** Fix the cause; never paper over it with a longer wait or a looser check.
