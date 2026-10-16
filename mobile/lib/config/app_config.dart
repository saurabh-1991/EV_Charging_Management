class AppConfig {
  const AppConfig._();

  // Keep tariff centralized so only config changes it, not UI.
  static const double ratePerUnitInr = 15.0;
}
