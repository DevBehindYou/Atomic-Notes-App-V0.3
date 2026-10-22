# Search keyboard focus

Android was opening and immediately closing the Home search keyboard. Its IME
reduced the available height below Home's 480px responsive breakpoint. Switching
from the fixed header to the scrolling header disposed the original TextField,
including its internally owned focus node and platform input connection.

One GlobalKey owned by Home now reparents the same header subtree between the
two exclusive layouts. The scrolling layout remains available on short screens;
search focus, selection, text and the platform input connection survive the move.
Controllers keep their existing Home lifetime and disposal.

Regression in `test/home_page_test.dart`: focus search, open a simulated 500px
keyboard across the breakpoint, assert identical EditableText state, focus and
visible keyboard, type and filter, then restore height and retain state/query.
The test failed before the fix with a defunct original editor and passes after.
Actual-phone recheck with the updated acceptance build remains a separate gate.
