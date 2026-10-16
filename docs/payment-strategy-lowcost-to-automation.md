# Payment Strategy: Low-Cost to Automation

## Option A: Low-Cost Launch (Default)

- No payment gateway integration cost.
- Residents pay via static UPI QR/link or bank transfer.
- App captures transaction reference and marks status as pending verification.
- Admin verifies and updates status to paid.

### Pros

- Fast launch
- Almost zero payment infra cost
- Minimal compliance overhead

### Trade-offs

- Manual reconciliation workload
- Delay between payment and confirmation

## Option B: Automated Gateway Upgrade (Future)

- Integrate with a gateway after society KYC completion.
- Create payment intents/orders from monthly bills.
- Update payment status using signed webhooks.
- Auto-reconcile successful/failed/expired payments.

### Pros

- Real-time payment updates
- Lower manual effort
- Better payment analytics

### Trade-offs

- Gateway processing fees
- Additional implementation and operational complexity

## Migration Design Guardrails

- Keep `payments` schema generic from day one.
- Keep `paymentSettings.gatewayEnabled` feature flag.
- Add gateway fields (`provider`, `gatewayOrderId`, `webhookEventId`) only when automation is enabled.
