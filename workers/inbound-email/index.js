// Cloudflare Email Worker: catch-all for *@trywince.app. Parses the email and hands it to
// parse-trial-receipt in the Postmark-shaped JSON that function already reads.
import PostalMime from "postal-mime";

export default {
  async email(message, env) {
    const mail = await PostalMime.parse(message.raw);
    const res = await fetch(`${env.FUNCTION_URL}?secret=${encodeURIComponent(env.INBOUND_SECRET)}`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        OriginalRecipient: message.to,
        ToFull: (mail.to ?? []).map((t) => ({ Email: t.address })),
        From: message.from,
        Subject: mail.subject,
        Date: mail.date,
        TextBody: mail.text,
        HtmlBody: mail.html,
      }),
    });
    // Bounce on failure so the sender knows it didn't land instead of it vanishing.
    if (!res.ok) message.setReject(`Wince couldn't process this email (${res.status}). Try again later.`);
  },
};
