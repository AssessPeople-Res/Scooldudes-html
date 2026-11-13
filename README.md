# Scooldudes.com (static archive)

Static HTML version of the Scooldudes.com site, converted from the original classic ASP / ASP.NET
pages so it can be hosted on GitHub Pages.

- Content pages, images, galleries, CSS and JS are kept as they were.
- Login, registration, forms, polls, the event calendar and payments needed the original server and
  database. Those links now go to `not-available.html`.
- `tools/convert-to-html.ps1` regenerates the site from the original source folder.
  `tools/conversion-report.txt` lists every converted page.

## Publish on GitHub Pages

Push this folder to a public GitHub repository. Then open **Settings → Pages**, set
**Source: Deploy from a branch**, and choose **Branch: `main` / root**.
