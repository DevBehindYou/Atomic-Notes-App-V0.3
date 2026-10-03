# R30 energy-tour navigation at large text

The bottom navigation Row overflows with double-sized text on portrait/narrow
screens. The unchanged main fixture reports a 62-pixel horizontal overflow at
390×844 and a 57-pixel overflow at 320×640. Text scaling is the Flutter test
environment's linear scale 2.0, not a physical-phone measurement.

Replace the bottom Row and its two Spacer widgets with Wrap, preserving spacing,
actions and the page indicator. Controls can occupy another row when needed.
The slide body remains scrollable. No wording, prices or navigation callbacks
change in this PR.

Test-only baseline `61ddcde753b2c1e36c20d6b547b00d8c3c8e42b3` against main
`3a26c2cd19ef59356815bda686e12f057cf1f8db`: portrait/narrow cases fail; normal
portrait and large-text landscape controls pass. All four pass after the fix.
The tests traverse every slide, verify Skip and Next/Finish are hittable, finish
the tour and return to the launching screen without rendering errors.

This does not establish full WCAG compliance, TalkBack behavior, real-phone
font rendering or persistence of the onboarding flag. The flag write is not
part of the fixture. This is an additional finding outside the original 28.
Rollback is to revert the layout PR; there is no stored-data change or production
action. The independent R8 billing-copy change remains a separate PR.
