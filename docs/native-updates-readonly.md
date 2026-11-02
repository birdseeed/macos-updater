# Read-only Updates presentation

PAT-2661 adds an Updates action beside Applications in the existing client.
Both open the same scrolling `LocalApplicationsView` with a presentation choice
and the exact same retained `LocalApplicationsController`. Applications remains
the view's default presentation. The disk-image chooser and Check controls remain
available in the original inspector. This is a bounded screen foundation; the
full native shell is separate PAT-2660 work.

The existing controller remains the sole scanner, single-flight and observation
owner. `updatesText` derives its values from `text`, changing only the heading to
Updates. Rows, claimed metadata, observation time, fixture provenance, folder
scope, explanations, status and scan controls are shared. There is no second
inventory, cached presentation, filesystem read or update coordinator. Opening
either sheet performs no scan. Only explicit Scan or Scan again calls the
existing controller, including Command-R; Done or Escape closes the sheet.

Updates says that update availability has not been checked. Unknown availability
counts every application copy in the current observation, including previous
rows shown while a refresh runs. It is zero before any observation and for an
empty observation. Ready for update is always zero and `allVerifiedUpToDate` is
always false, including empty, incomplete and unavailable observations. Duplicate
copies and safe unverified claims remain visible as literal text using system
fonts. A failed or incomplete observation retains the existing scanner's status
and explanations; it supplies no update eligibility or installation authority.

No catalogue matching, publisher verification, download, transaction, productive
Start action, schedule, preference session or network operation is connected.
The existing pure fixture and policy foundations do not become productive
owners through this screen. Native interaction, catalogue integration, verified
update eligibility, installation and recovery remain separate work and proof
gates. Source implementation and synthetic checks do not establish native launch,
installed behaviour, complete PAT-2661 acceptance or customer release readiness.

The parent owns focused and full verification, immutable independent correctness
and security review, native guest acceptance under the existing shared budget,
and any publication. No build, candidate execution or native proof was performed
by the implementation leaf.
