# CurseForge banners

Source of the images in `docs/images/`. To change a banner, edit `banners.html`, put
Space Grotesk and Inter (variable, latin, woff2 – e.g. from the npm packages
`@fontsource-variable/space-grotesk` and `@fontsource-variable/inter`, OFL) into `fonts/`
next to it as `space-grotesk-latin-wght-normal.woff2` and `inter-latin-wght-normal.woff2`,
and render each `.banner` section at 2x, e.g. with Playwright:

```python
page = browser.new_page(device_scale_factor=2)
page.goto("file:///path/to/banners.html")
page.locator("#b1").screenshot(path="gatherline-1.png")
```

The banners are illustrations in Gatherline's look, not screenshots; route names and
numbers in them are made up.
