# OneSpace website

The public website for OneSpace — https://boyofkay.github.io/onespace-app/

Static HTML on GitHub Pages (free). English with an Arabic switch (right to left).

- `build.py` holds all the content (English and Arabic). Edit it, run `python3 build.py`, commit.
- Pages: home, privacy policy, terms of use, support (contact form), delete your account (needed for Google Play), 404.
- The contact and account-deletion forms send to the same support inbox as the app
  (Supabase `submit_public_support`, rate-limited; nobody can read messages through the API).
- The app code lives in the private repository BoyofKay/OneSpace.
