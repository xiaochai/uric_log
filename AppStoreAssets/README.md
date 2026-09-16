# App Store Assets

Store generated App Store screenshots by app version:

```text
versions/<version>/<locale>/*.png
```

Current assets are under `versions/1.1.0/`. Shared generation scripts live in
`tools/` so generated images from different releases do not overwrite each
other.

Example:

```bash
swift AppStoreAssets/tools/generate.swift \
  <raw-screenshot-directory> \
  AppStoreAssets/versions/1.1.0
```
