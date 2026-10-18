const escapeHtml = (value: string) => value
  .replaceAll("&", "&amp;")
  .replaceAll("<", "&lt;")
  .replaceAll(">", "&gt;")
  .replaceAll('"', "&quot;")
  .replaceAll("'", "&#39;");

export type AuthEmailKind = "resetPassword" | "verifyEmail";

export function buildAuthEmail(kind: AuthEmailKind, link: string) {
  const safeLink = escapeHtml(link);
  const isReset = kind === "resetPassword";
  const subject = isReset ? "Reset your PlayUp password" : "Verify your PlayUp email";
  const action = isReset ? "Reset password" : "Verify email";
  const intro = isReset
    ? "Use the secure button below to choose a new password for your PlayUp account."
    : "Confirm this email address to finish setting up your PlayUp account.";
  const expiry = isReset ? "This link expires in one hour and can only be used once." : "This verification link can only be used once.";
  const text = `${intro}\n\n${action}: ${link}\n\n${expiry}\n\nIf you did not request this, you can ignore this email.\n\nPlayUp Support`;
  const html = `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f3f6f4;font-family:Arial,Helvetica,sans-serif;color:#14221a"><div style="display:none;max-height:0;overflow:hidden;opacity:0">${subject}</div><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="background:#f3f6f4;padding:40px 12px"><tr><td align="center"><table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="max-width:560px;background:#fff;border:1px solid #e1e9e3;border-radius:18px;overflow:hidden"><tr><td style="height:5px;background:#22e879;font-size:0">&nbsp;</td></tr><tr><td style="padding:32px 36px 8px"><a href="https://play-up.fit" style="display:inline-block"><img src="https://play-up.fit/playup-email-logo.png" width="184" alt="PlayUp" style="display:block;width:184px;height:auto;border:0"></a></td></tr><tr><td style="padding:20px 36px 32px"><p style="margin:0 0 10px;color:#168447;font-size:12px;font-weight:700;letter-spacing:1.1px">PLAYUP ACCOUNT SECURITY</p><h1 style="margin:0 0 14px;font-size:27px;line-height:1.25">${subject}</h1><p style="margin:0 0 24px;color:#4e5d53;font-size:16px;line-height:1.65">${intro}</p><p style="margin:0 0 24px"><a href="${safeLink}" style="display:inline-block;border-radius:10px;background:#168447;color:#fff;padding:14px 24px;font-size:15px;font-weight:700;text-decoration:none">${action}</a></p><p style="margin:0 0 8px;color:#536258;font-size:14px;line-height:1.6">${expiry}</p><p style="margin:0 0 24px;color:#536258;font-size:14px;line-height:1.6">If you did not request this, you can ignore this message.</p><p style="margin:0;color:#536258;font-size:14px">Need help? <a href="mailto:info@creativnetworks.com" style="color:#126a38">Contact PlayUp Support</a>.</p></td></tr><tr><td style="border-top:1px solid #e8eee9;padding:18px 36px;background:#fbfcfb;color:#748078;font-size:12px">PlayUp Support · Automated account email</td></tr></table></td></tr></table></body></html>`;
  return {subject, text, html};
}

export function playUpActionLink(firebaseLink: string, mode: AuthEmailKind) {
  const parsed = new URL(firebaseLink);
  const code = parsed.searchParams.get("oobCode");
  const apiKey = parsed.searchParams.get("apiKey");
  if (!code || !apiKey) throw new Error("Generated Firebase action link is incomplete.");
  const url = new URL("https://play-up.fit/auth/action");
  url.searchParams.set("mode", mode);
  url.searchParams.set("oobCode", code);
  url.searchParams.set("apiKey", apiKey);
  return url.toString();
}
