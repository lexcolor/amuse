import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Calls [callback] whenever the page comes back to the foreground (the
/// phone was unlocked, the tab was switched to).
void onPageVisible(void Function() callback) {
  web.document.addEventListener(
    'visibilitychange',
    ((web.Event _) {
      if (web.document.visibilityState == 'visible') callback();
    }).toJS,
  );
}
