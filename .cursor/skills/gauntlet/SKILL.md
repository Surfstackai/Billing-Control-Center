---
name: gauntlet
description: Use when the user says run the gauntlet, gauntlet this, improve until it beats the reference, or requests independent iterative quality review. Builds against a concrete quality bar, delegates review to the gauntlet-critic subagent, fixes the biggest gap, and repeats until the implementation wins.
---

Run a Gauntlet Loop on the requested work.

The quality bar is the most important input.

A valid quality bar must be:

1. Named: a specific product, screen, repository, artifact, implementation, test suite, or other concrete reference.
2. Fetchable: the actual reference can be inspected.
3. Comparable: the implementation and reference can reasonably be compared.

If the user supplied a reference, use it.

Do not replace the user's reference with a vague standard such as "professional," "best practice," "modern UI," or "Salesforce-like."

If the task has no usable reference, identify the best concrete comparison available from the user's request or repository. Do not invent inaccessible references.

Then:

1. Inspect the existing implementation and relevant repository context.
2. Identify the smallest independently judgeable portion of the requested work.
3. Implement or improve that portion.
4. Run the appropriate validation, tests, linting, builds, or deployment checks.
5. Delegate evaluation to the gauntlet-critic subagent with fresh context.
6. Give the critic:
   - the user's original goal
   - the exact quality bar
   - the files or rendered implementation to inspect
   - relevant validation results
   - access to the actual reference
7. Do not tell the critic why implementation decisions were made.
8. Do not ask the builder to grade its own work.
9. If the critic returns REFERENCE:
   - take its BIGGEST GAP
   - fix that gap
   - validate again
   - invoke a fresh gauntlet-critic review
10. Continue until the critic returns CONFIRMED or the user explicitly stops the loop.

Do not stop merely because:
- the code compiles
- tests pass
- the requested feature exists
- an arbitrary number of iterations has occurred
- the implementation is "good enough"

Tests and compilation are necessary gates, not the quality bar.

Do not broaden scope unnecessarily. Preserve unrelated working behavior.

For Salesforce work:

* **Respect the target org explicitly named by the user.**

  * Never deploy to, modify, or validate against a different org unless the user explicitly changes the target.
  * Before any actual deployment, verify the authenticated org matches the intended target.
  * If the target cannot be verified, stop before deployment.

* **Distinguish three different validation stages:**

  * **Local validation**: source structure, linting, static analysis, tests that do not require an org.
  * **Dry-run validation**: Salesforce deployment validation/check-only against the target org without committing changes.
  * **Actual deployment**: metadata is committed to the target org.
  * Never describe one stage as another.

* **A successful Salesforce deployment is not proof that the feature is correct.**

  * Deployment success proves metadata was accepted by Salesforce.
  * It does **not** prove the UX, navigation, permissions, visibility, data behavior, product design, or acceptance criteria are correct.
  * After deployment, validate the actual user-facing behavior and the original acceptance criteria wherever possible.

* **Preserve existing Salesforce security and sharing behavior unless the requested change explicitly requires modifying it.**

  * Do not weaken OWD, sharing rules, CRUD, FLS, permission sets, profiles, restriction rules, or record access merely to make a feature or test pass.
  * Security changes must be intentional and traceable to a requirement.

* **Prefer standard Salesforce capabilities first.**

  * Wherever practical, use standard Salesforce objects, fields, relationships, configuration, UI, Flow, validation rules, formulas, Dynamic Forms, Lightning pages, permission sets, and other declarative platform capabilities.
  * Do not create custom objects, custom fields, Apex, custom persistence models, or bespoke UI when an appropriate standard Salesforce capability already satisfies the requirement.
  * Custom implementation is justified when the standard capability cannot meet the required behavior, creates unacceptable product limitations, or would cause the functionality to fail.
  * **Apex should be a last resort, not the default.**

* **Do not guess when Salesforce platform behavior is ambiguous.**

  * Check the current official Salesforce Developer documentation directly when platform limits, metadata behavior, packaging behavior, APIs, security behavior, standard-object capabilities, or supported implementation patterns are unclear.
  * Prefer official Salesforce documentation over blogs, forum posts, remembered behavior, or assumptions.

* **When a test or deployed feature fails, check access and visibility before assuming the implementation is broken.**

  * Verify the object exists and is deployed.
  * Verify the field exists and is deployed.
  * Verify object CRUD access.
  * Verify field-level security.
  * Verify permission-set or profile assignment where relevant.
  * Verify Lightning page/component visibility and record-type applicability where relevant.
  * Verify the running user can actually see the object, field, record, and component.
  * Do not "fix" a visibility problem by unnecessarily rebuilding working metadata.

* **Treat package compatibility as part of the implementation when the work is intended for a managed package.**

  * Do not rely on sandbox-only assumptions, org-specific IDs, unmanaged dependencies, or metadata that cannot be packaged.
  * Flag anything that works in the target sandbox but would create a managed-package or subscriber-org problem.

At completion report:
- what was changed
- validations performed
- final critic verdict
- the reference used
- any remaining material differences
