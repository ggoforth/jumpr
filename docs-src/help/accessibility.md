---
title: The Accessibility permission
lede: Why Jumpr needs the Accessibility permission, how to grant it, and what it does with it.
order: 1
---

Jumpr needs the Accessibility permission for two things: to find the buttons, links and icons on your screens, and to click the one you pick. It is the only permission Jumpr asks for.

## Grant it

1. Open System Settings → Privacy & Security → Accessibility.
2. Turn on Jumpr.

When you open Jumpr without the permission, macOS asks for it and Jumpr opens its panel. Until you grant it, the panel has an Open Accessibility Settings button that takes you to the right place.

> **Panel shows Relaunch Jumpr?** If Jumpr still can't start listening for the hotkey after you grant the permission, the panel shows a **Relaunch Jumpr** button.

If you turn the permission off while Jumpr runs, Jumpr stops listening for the hotkey and opens its panel.

![Jumpr switched on in System Settings.](accessibility-toggle.webp)

## What Jumpr does with it

- It reads the screen on your Mac to place labels. What it reads is not recorded, stored or sent anywhere.
- It does not record your screen.
- It keeps a small activity log on your Mac. [Reporting a problem](reporting-a-problem.md#the-log) lists what is in it.

## Web-based apps

Jumpr turns on accessibility information in web-based apps so it can see them. When you pause or quit Jumpr, it turns that off again. See [Known limits](known-limits.md#web-pages-and-web-based-apps) for when it can't.
