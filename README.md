# FocusBlocker

A tiny macOS focus timer built with Swift, AppKit, and Carbon.

macOS will ask for notification permission the first time the app runs.
If notifications do not appear, check System Settings > Notifications > FocusBlocker.

Build the app bundle with:

```sh
make build
```

Run it with:

```sh
make run
```

Install it to Applications with:

```sh
make install
```

The app runs as a menu bar item. To start it when you log in, add `FocusBlocker.app` in System Settings > General > Login Items.

For a scriptable startup install instead:

```sh
make launch-agent
```
