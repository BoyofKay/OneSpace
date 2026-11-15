# R59 — Your data and account: test script

Use a test account if possible. Deleting Ahmed's or Kandice's real account cannot be undone after 7 days.

| # | Do | Expect |
|---|---|---|
| 1 | Settings › Privacy › Your data and account › Download | "Saved to Downloads/OneSpace/OneSpace-my-data-YYYY-MM-DD.json". Open it in Files: your notes, events, reminders, etc.; no device tokens. |
| 2 | Delete my account | Page asks to type DELETE; Delete stays off until you do. |
| 3 | Type DELETE › Delete | You are signed out. |
| 4 | Sign in again within 7 days | Dialog "Your account is scheduled for deletion" › Keep my account › snackbar "Deletion cancelled". |
| 5 | Settings › Your data and account while pending | Red card with the date and "Keep my account". |
| 6 | (After 7 days, test account only) | Private items gone; shared items still visible to the partner as "Former partner"; the account can no longer sign in. |
