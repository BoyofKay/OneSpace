#!/usr/bin/env python3
"""Builds every Supabase Auth email template from one OneSpace shell.

Run from the repository root:  python3 supabase/email-templates/build.py
Then paste each generated .html into Supabase > Authentication > Emails >
Templates (QA first, Production only after QA is accepted), using the
subject listed in README.md. Do not hand-edit the generated .html files.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
TAGLINE = "Two of Us. One Space."  # must equal OneSpaceBrand.tagline
LOGO = "https://onespace.live/assets/icon-512.png"
SUPPORT = "support@onespace.live"
SITE = "https://onespace.live"

IGNORE = ("If you did not request this message, you can safely ignore it. "
          "We will never ask you to share a password or verification code.")
NOT_YOU = ("If this was not you, reset your password straight away and contact "
           f'<a href="mailto:{SUPPORT}" style="color:#234d82">{SUPPORT}</a>.')


def button(label: str) -> str:
    return (
        '<table role="presentation" cellspacing="0" cellpadding="0"><tr>'
        '<td style="background:#234d82;border-radius:11px">'
        '<a href="{{ .ConfirmationURL }}" style="display:inline-block;padding:16px 24px;'
        'font-size:16px;line-height:1.25;font-weight:700;color:#fff;text-decoration:none">'
        f'{label}</a></td></tr></table>\n'
        '<p style="font-size:13px;line-height:1.7;color:#5c6e83;margin:24px 0 5px">'
        'If the button does not work, open this secure link:</p>\n'
        '<p style="font-size:12px;line-height:1.65;margin:0;word-break:break-all">'
        '<a href="{{ .ConfirmationURL }}" style="color:#234d82">{{ .ConfirmationURL }}</a></p>'
    )


def code_box() -> str:
    return ('<p style="margin:0;padding:16px 20px;background:#f3f6fa;border-radius:11px;'
            'font:700 28px/1.2 monospace;letter-spacing:6px;color:#14213d;'
            'display:inline-block">{{ .Token }}</p>')


def shell(title: str, heading: str, intro: str, action: str, footnote: str) -> str:
    return f"""<!doctype html>
<html lang="en">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>{title}</title></head>
<body style="margin:0;padding:28px 12px;background:#f3f6fa;font-family:Arial,Helvetica,sans-serif;color:#14213d">
<table role="presentation" cellspacing="0" cellpadding="0" width="100%" style="max-width:560px;width:100%;margin:0 auto;background:#fff;border:1px solid #e1e8ef;border-radius:18px">
<tr><td style="padding:30px 30px 18px">
<table role="presentation" cellspacing="0" cellpadding="0"><tr>
<td style="width:62px;vertical-align:middle;padding-right:13px"><img src="{LOGO}" alt="OneSpace" width="58" height="58" style="display:block;width:58px;height:58px;border:0"></td>
<td style="vertical-align:middle"><strong style="font-size:25px;line-height:1.3;color:#14213d">OneSpace</strong><br><span style="font-size:12px;line-height:1.55;color:#566a82">{TAGLINE}</span></td>
</tr></table>
<h1 style="font-size:26px;line-height:1.3;margin:29px 0 12px;color:#14213d">{heading}</h1>
<p style="font-size:16px;line-height:1.65;color:#43556c;margin:0 0 22px">{intro}</p>
{action}
<p style="font-size:13px;line-height:1.7;margin:24px 0 0;color:#5c6e83">{footnote}</p>
</td></tr>
<tr><td style="padding:18px 30px 26px;border-top:1px solid #e1e8ef"><strong style="font-size:17px;color:#14213d">OneSpace</strong><br>
<span style="font-size:12px;line-height:1.7;color:#566a82">{TAGLINE}</span><br>
<a href="{SITE}" style="font-size:12px;color:#234d82;text-decoration:none">onespace.live</a><br>
<a href="mailto:{SUPPORT}" style="font-size:12px;color:#566a82;text-decoration:none">{SUPPORT}</a>
</td></tr></table></body></html>
"""


# file name -> (subject, heading, intro, action, footnote)
TEMPLATES = {
    "confirmation.html": (
        "Confirm your OneSpace email address", "Confirm your email",
        "Confirm that <strong>{{ .Email }}</strong> belongs to you to finish creating your "
        "OneSpace account. If you opened your partner's invitation, it will be saved while "
        "you confirm your email and sign in.",
        button("Confirm my email"), IGNORE),
    "invite_user.html": (
        "You're invited to OneSpace", "You're invited to OneSpace",
        "An account has been created for <strong>{{ .Email }}</strong>. Accept the invitation "
        "to choose your password and open OneSpace.",
        button("Accept invitation"), IGNORE),
    "magic_link.html": (
        "Your OneSpace sign-in link", "Sign in to OneSpace",
        "Use this secure link to sign in as <strong>{{ .Email }}</strong>. It works once and "
        "expires shortly.",
        button("Sign in"), IGNORE),
    "email_change.html": (
        "Confirm your new OneSpace email address", "Confirm your new email",
        "Confirm that you want to change your OneSpace sign-in email from "
        "<strong>{{ .Email }}</strong> to <strong>{{ .NewEmail }}</strong>.",
        button("Confirm new email"), IGNORE),
    "password_recovery.html": (
        "Reset your OneSpace password", "Reset your password",
        "We received a request to reset your OneSpace password. Use this secure link to "
        "choose a new password. Your existing password remains valid until the reset succeeds.",
        button("Reset my password"), IGNORE),
    "reauthentication.html": (
        "Your OneSpace verification code", "Your verification code",
        "Enter this code in OneSpace to confirm it's you. It expires shortly.",
        code_box(), IGNORE),
    "password_changed_notification.html": (
        "Your OneSpace password was changed", "Your password was changed",
        "The password for <strong>{{ .Email }}</strong> was just changed.",
        "", NOT_YOU),
    "email_changed_notification.html": (
        "Your OneSpace email address was changed", "Your email was changed",
        "Your OneSpace sign-in email was changed from <strong>{{ .OldEmail }}</strong> to "
        "<strong>{{ .Email }}</strong>.",
        "", NOT_YOU),
}

if __name__ == "__main__":
    for name, (subject, heading, intro, action, foot) in TEMPLATES.items():
        (HERE / name).write_text(shell(subject, heading, intro, action, foot), encoding="utf-8")
        print(f"{name:40} {subject}")
