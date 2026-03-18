# Wind Force Compatibility Expansion Roadmap v1

## Purpose

This document proposes a milestone-based roadmap for expanding Wind Force from its current Instinct 2 and Instinct 2X support to a broader set of Garmin watches used for surface-based watersports. It is intended to guide later updates to `docs/execution_plan.md`, not to replace that plan. The focus is deliberately limited to watches used for kayaking, stand-up paddleboarding, surfing, whitewater, boating, and sailing. Diving-first watches are out of scope for this roadmap.

## Current Baseline

The app currently declares only `instinct2` and `instinct2x` in `manifest.xml`. The implementation is already reasonably portable because it uses a text-only data field, dynamic text measurement, and width-based slot reduction instead of device-specific drawing logic. The main compatibility constraints are the manifest product list, background-service architecture, screen geometry differences, and the need to verify that the target devices support the required background, communications, and positioning behaviors.

The current UI and rendering assumptions are still biased toward Instinct-class displays. That is a strength for the first expansion wave because the lowest-risk targets are other surface-watersports watches that are closest to the existing Instinct form factor and field layouts.

For roadmap purposes, the compatibility floor is Connect IQ API `3.2.0`. Devices below API `3.2.0` are intentionally excluded from the expansion plan, even if they are nominally related Garmin watch families. This keeps the roadmap aligned with the app's background-storage requirements and avoids spending effort on older legacy devices that are outside the intended support direction.

## Scope and Non-Goals

This roadmap covers surface-based watersports watches only. The intended target activities are kayak, SUP, surf, whitewater, boat, and sail where the device runs a normal activity profile and the data field remains visible during use.

This roadmap does not cover dive-mode support, Edge bike computers, handheld GPS units, or general-purpose compatibility expansion to every Connect IQ watch. Those may be addressed later, but they should not shape the first compatibility rollout.

## Guiding Principles

Expand support in small, testable waves. Group devices by layout and usage similarity rather than by release year.

Prefer device families that preserve the current product value. A kayak and paddling user on an Instinct-style watch is a closer fit than a technically compatible device with very different field behavior.

Treat manifest expansion as the last step of each milestone, not the first. A device should be added to the manifest only after build, simulator, and layout validation are complete for that class.

Keep the implementation generic where possible. If a problem can be solved with better runtime measurement and layout logic, do that before introducing device-specific branches.

Do not plan support for devices below API `3.2.0`. That is a deliberate roadmap boundary, not a temporary omission.

## Proposed Milestones

## Milestone 0: Compatibility Groundwork

The goal of this milestone is to reduce avoidable risk before adding any new devices. At the end of the milestone, the repository should have a clear compatibility target matrix, a validation checklist, and any low-level compatibility fixes needed across all later waves.

The main work in this milestone is to audit the background-service and storage assumptions against the target watch set, raise `minApiLevel` from `3.1.0` to `3.2.0`, and define the simulator test matrix by device geometry class. This is also the right place to review whether the current slot thresholds and font selection are too Instinct-2X-specific and should become more measurement-driven before expansion starts.

The output should be a compatibility appendix or section in the execution plan that names the first-wave devices, the reasons they were selected, the acceptance criteria for adding them, and the known risks to watch for in later milestones. That appendix should also state explicitly that the roadmap excludes devices below API `3.2.0`, because that exclusion is part of the compatibility strategy rather than an unresolved question.

This milestone should not add new manifest products yet unless a no-risk candidate is validated during the same pass.

## Milestone 1: Instinct Family Surface-Watersports Expansion

This is the first shipping expansion wave and should target the watches closest to the current product and layout model. The recommended candidates are Instinct 2S, Instinct E, Instinct Crossover, and Instinct 3 Solar variants. These watches are relevant for paddling and surface watersports, and their display behavior is close enough to the existing support base to keep the risk manageable.

The main work is to validate field layout on smaller or slightly different Instinct geometries, especially narrow fields and small-body variants. Instinct 2S is the most important early target because it is a high-probability compatibility win with a smaller semioctagonal display. Instinct E and Instinct 3 Solar should follow once the same rendering logic is shown to fit their field shapes without clipping or unreadable font drops.

This milestone should include the first production-quality compatibility matrix in the README and release notes. It should also document which Instinct-family variants were tested in simulator, which were validated by SDK layout inspection only, and which are intentionally deferred.

The milestone is complete when the first-wave Instinct-family product IDs are added to `manifest.xml`, release builds succeed for those devices, and the manual validation checklist passes for at least one representative device in each added geometry class.

## Milestone 2: AMOLED and Newer Instinct-Class Variants

This milestone should broaden support to surface-watersports watches that are still close to the Instinct audience but introduce different display expectations. The main candidates are Instinct 3 AMOLED variants and any remaining Instinct Crossover variants not already covered in Milestone 1.

The core question here is not whether the app can compile, but whether the text-first presentation still feels correct on brighter, higher-density displays with different field proportions. The current implementation may technically work without changes, but this milestone should confirm whether layout behavior needs tuning so larger or more modern screens do not underuse available space.

This milestone should be used to decide whether the app remains a single generic data field for all supported watches or whether a small amount of device-family-specific layout tuning is justified. If device-specific behavior is introduced, it should be minimal and only after the generic measurement path proves insufficient.

The milestone is complete when the added AMOLED or newer Instinct-class devices show stable rendering across common field sizes and the resulting UX still matches the app’s core use case rather than merely “fitting on screen.”

## Milestone 3: Premium Surface and Marine Watch Expansion

This milestone extends support to premium surface-watersports watches with strong relevance for boating and sailing. The recommended candidates are fēnix 7 family, fēnix 8 family, quatix 7 family, and quatix 8 family. These devices are valuable because they match the target domain well, especially for marine users, but they are a larger step away from the current Instinct-tuned assumptions.

The main technical risk in this milestone is not functionality but presentation quality across different data-field layouts. Round high-resolution watches often have very different field shapes, and some premium devices support a wider range of activity and data-field slot arrangements. This milestone should therefore include explicit simulator validation of representative larger round layouts rather than assuming that successful compilation is enough.

The implementation goal should remain generic if possible. Wider displays may reveal that the current `THRESHOLD_2_SLOT` and `THRESHOLD_3_SLOT` logic leaves screen space unused or chooses a lower slot count than necessary. If that happens, this milestone should replace the remaining fixed-threshold bias with stronger runtime layout measurement.

This milestone is complete when at least one fēnix-class and one quatix-class geometry are validated end to end, the manifest is expanded accordingly, and the support statement in the README is updated to distinguish “surface watersports supported” from broader Garmin compatibility.

## Milestone 4: Compatibility Hardening and Release Preparation

This milestone consolidates the earlier waves into a releaseable support policy. By this point the app should have a wider manifest, but the project still needs a disciplined definition of what “supported” means and how regressions will be prevented.

The work here should include finalising the support matrix, adding or updating tests that protect the most portability-sensitive rendering logic, and documenting known limitations for partially validated devices. It should also include a review of manual validation steps so future compatibility additions follow the same standard instead of becoming ad hoc.

This is the right milestone to prepare a release that explicitly markets the broader surface-watersports watch support. Release notes should call out newly added families, any remaining exclusions, and any behavioural differences that users may notice on smaller or larger watch layouts.

The milestone is complete when the roadmap items that were promoted into the execution plan are reflected in README, RELEASE, and execution-plan documentation, and when the team can state which families are officially supported with confidence.

## Candidate Device Order

The recommended shipping order is:

1. Instinct 2S
2. Instinct E
3. Instinct 3 Solar
4. Instinct Crossover
5. Instinct 3 AMOLED
6. fēnix 7 family
7. fēnix 8 family
8. quatix 7 family
9. quatix 8 family

This order favors the watches that are closest to the current product and strongest for paddling first, then expands toward premium marine and sailing watches once the layout model is hardened.

All devices in this order are expected to meet the API `3.2.0` floor. Any candidate that falls below that floor should be excluded rather than added as a special case.

## Cross-Milestone Technical Work

Several tasks should be treated as shared work items that may start in one milestone and finish in another.

The first shared task is manifest discipline. Exact Connect IQ product IDs should be confirmed from the installed SDK before each wave lands, because the shipping roadmap should use Garmin marketing names while code changes need SDK product identifiers.

The second shared task is layout generalisation. The current font selection and overflow control are strong, but the width thresholds in `source/DisplayRenderer.mc` are still based on the current support set. If broader watch classes expose weak spots, runtime measurement should take priority over adding more thresholds.

The third shared task is validation infrastructure. The project should maintain a lightweight compatibility checklist that covers build, simulator launch, GPX playback, background fetch, no-GPS fallback, and text fit in at least one narrow and one wide data-field size.

## Risks and Watchpoints

The biggest practical risk is adding too many devices to the manifest before they are meaningfully tested. That creates support obligations without confidence.

The second risk is assuming that all watersports watches behave like Instinct devices. Premium round displays may be functionally compatible but still need layout tuning to feel intentional.

The third risk is failing to enforce the API `3.2.0` floor consistently. If lower-API legacy devices are reintroduced as exceptions, the roadmap will regain the same background-storage and validation ambiguity that this version is trying to remove.

The fourth risk is scope drift. If the expansion starts pulling in diving, bike, or handheld devices, the roadmap will lose focus and the execution plan will become harder to validate.

## Success Criteria

This roadmap should be considered successful when the execution plan can be updated milestone by milestone without redoing the compatibility strategy from scratch.

The first visible success is a clean Instinct-family expansion for surface watersports with a clear README support statement.

The second visible success is a later release that adds fēnix and quatix surface-watersports watches without needing a major architectural rewrite.

## Revision Note

Created on 2026-03-17 to provide a milestone-based compatibility expansion roadmap focused on surface-based watersports watches only. Updated on 2026-03-17 to set Connect IQ API `3.2.0` as the explicit compatibility floor and exclude lower-API devices from the roadmap. This document is intentionally strategic and should be translated into concrete execution-plan steps as each milestone begins.
