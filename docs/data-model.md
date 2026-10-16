# Data Model

## Collections

- `societies/{societyId}`
  - name, timezone, defaultRatePerUnit, billingDay
- `users/{userId}`
  - societyId, role, fullName, flatNumber, phone
- `vehicles/{vehicleId}`
  - societyId, ownerId, vehicleNumber, chargerType
- `chargingSlots/{slotId}`
  - societyId, slotDate, startTime, endTime, bookedBy, status
- `chargingSessions/{sessionId}`
  - societyId, userId, vehicleId, startTime, endTime, startMeter, endMeter, units, rateSnapshot, amount
- `monthlyBills/{billId}`
  - societyId, userId, billingMonth, totalUnits, totalAmount, dueDate, status, invoicePath
- `paymentIntents/{intentId}`
  - societyId, billId, amount, method, status
- `payments/{paymentId}`
  - societyId, billId, userId, amount, method, txnRef, status, paidAt, verifiedBy
- `paymentSettings/{societyId}`
  - upiId, upiQrPath, bankAccountMasked, ifscMasked, gatewayEnabled

## Notes

- `gatewayEnabled=false` for launch phase (low-cost model).
- `txnRef` should be unique per society to reduce duplicate entries.
- Future automation can append gateway metadata fields without migration blockers.
