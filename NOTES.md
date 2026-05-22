
## Mercury Transaction Sync — Production Test Required
- Mercury sandbox `/accounts/{id}/transactions` returns 404 for all accounts
- Confirmed via direct curl — accounts endpoint works fine, transactions endpoint does not
- Theory: sandbox restriction only, will work in production with real accounts
- **MUST TEST in production after go-live** — run Sync button and verify transactions populate

## Production Go-Live Checklist — Everything That Needs To Change

### Environment Variables (all currently localhost/sandbox/test values)
- `MERCURY_API_KEY` — swap sandbox key for real production Mercury API key
- `MERCURY_SANDBOX` — set to `false`
- `MERCURY_WEBHOOK_SECRET` — set to real webhook secret from Mercury production dashboard
- `MERCURY_ACCOUNT_NUMBER` — real Mercury checking account number (shows in portal payment instructions)
- `MERCURY_ROUTING_NUMBER` — real Mercury routing number (shows in portal payment instructions)
- `PORTAL_BASE_URL` — change from `http://localhost:4000` to real domain (e.g. `https://app.gnomeautomation.io`)
- Email delivery — currently dev mailbox only, needs real provider (Mailgun or Postmark) configured

### Mercury Dashboard (production)
- Register webhook URL: `https://yourdomain.com/webhooks/mercury`
- Copy the webhook secret Mercury generates and set as `MERCURY_WEBHOOK_SECRET`
- Generate a new production API key and set as `MERCURY_API_KEY`

### Things That Are Currently Localhost-Only
- Invoice email "View & Pay Invoice" button links to `http://localhost:4000/portal/invoices/:id`
- Portal magic-link sign-in emails link to `http://localhost:4000/portal/...`
- Both are controlled by `PORTAL_BASE_URL` config — one change fixes both

### Post Go-Live Tests Required
- Mercury Sync button — verify accounts AND transactions populate from production API
- Webhook — send a real payment to Mercury, verify it hits our webhook, PaymentMatcherWorker runs, invoice closes
- Invoice email portal link — verify green button URL uses real domain, not localhost
- Portal magic-link email — verify link uses real domain
