# EV Charging Management

Cross-platform mobile platform for society EV charging operations with:

- Charging session logging and unit-based billing
- Slot booking and availability management
- Monthly invoice generation
- Low-cost payment collection (UPI/bank transfer, no gateway at launch)
- Future-ready automation path for payment gateway integration

## Repository Structure

- `mobile/` Flutter app foundation (feature-first structure)
- `infra/firebase/` Firestore security rules and indexes
- `services/billing/` Python billing service for monthly invoice generation
- `docs/` product, data model, deployment, and payment strategy docs

## Planned Stack

- Flutter (Android + iOS)
- Firebase Auth, Firestore, Cloud Storage
- Python billing service (report + invoice generation)

## Payment Strategy

1. Launch with static UPI link/QR and bank transfer details.
2. Resident uploads transaction reference in app.
3. Admin verifies and marks payment as settled.
4. Optional future upgrade to payment gateway + webhook automation.
