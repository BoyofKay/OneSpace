# OneSpace website

The public website for OneSpace — https://boyofkay.github.io/onespace-app/

Static HTML on GitHub Pages (free). English with an Arabic switch (right to left).

- `build.py` holds all the content (English and Arabic). Edit it, run `python3 build.py`, commit.
- Pages: home, privacy policy, terms of use, support (contact form), delete your account (needed for Google Play), 404.
- The contact and account-deletion forms send to the same support inbox as the app
  (Supabase `submit_public_support`, rate-limited; nobody can read messages through the API).
- The app code lives in the private repository BoyofKay/OneSpace.

## Product website and organic search roadmap

The SEO landing pages live alongside the generated pages:
- `couples-app.html` — couples planning and connection
- `long-distance-relationship-app.html` — LDR use cases
- `shared-calendar-for-couples.html` — calendar and shared scheduling
- `feature-tour.html` and `getting-started.html` — product education

**Generator caveat:** `build.py` regenerates the original core pages and sitemap but does not generate the standalone landing pages. Keep `build.py` and the generated homepage in sync when editing. Run `python3 build.py` from the `website` directory and inspect the diff before committing.

### Before launch
1. Verify GitHub Pages publishing source and deployed URLs. Do not assume files in the private repository are publicly deployed.
2. Check all pages and the sitemap over HTTPS, including mobile navigation and support forms.
3. Verify the website property in Google Search Console, then submit `sitemap.xml` and inspect key URLs.
4. Verify canonical URLs, robots directives, unique page titles and mobile performance.
5. Add authentic screenshots **only after** removing or masking names, avatars, messages, contact details, addresses and notifications. Do not rely on CSS blur to protect private information; sanitize image files before publishing.
6. Review feature claims against current working app behavior, particularly calendar integration, notification quiet hours, trips and iPhone availability.
7. Confirm final brand domain before publishing extensively: switching from the GitHub Pages URL requires redirects and canonical updates.
8. Track impressions, clicks, queries and conversions. No rankings are guaranteed.
9. Translate standalone English landing pages into reviewed Arabic pages with distinct URLs and hreflang when ready. Avoid language-switch-only pages for bilingual search indexing.

No analytics, advertising pixels, external SEO service or paid infrastructure is required for the first phase.
