# Opening Insomnia the first time

Insomnia v1 is **not notarized** — there's no Apple Developer account behind it
yet. The release builds *are* ad-hoc code-signed (which gives the bundle a
stable identity so "Launch at Login" keeps working across updates), but ad-hoc
signing is not the same as Apple notarization, so Gatekeeper will warn on first
launch.

This is a one-time step.

## Fix A — right-click → Open (recommended)

1. In Finder, **right-click** (or Control-click) `Insomnia.app`.
2. Choose **Open**.
3. In the dialog that appears, click **Open** again.

macOS remembers your choice; from then on the app launches normally.

## Fix B — remove the quarantine flag (terminal)

```sh
xattr -dr com.apple.quarantine /Applications/Insomnia.app
```

Then launch the app normally.

## Why

`open` and double-click route unsigned/un-notarized apps through Gatekeeper,
which refuses them by default. Right-click → Open (or clearing the quarantine
attribute) tells macOS you trust this specific app.

If you'd rather not take our word for it: the source is right here — build it
yourself with `swift build -c release && ./Bundle/bundle.sh` and run your own
`dist/Insomnia.app`.

Notarized, signed builds are on the roadmap.
