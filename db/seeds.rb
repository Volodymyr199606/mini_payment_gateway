# This file should ensure all the data necessary to run the application
# in its default state is loaded. The data can then be loaded with the bin/rails
# db:seed command (or created alongside the database with db:setup).

puts "Creating merchants..."

# Create test merchants with API keys
merchant1, api_key1 = Merchant.create_with_api_key(
  name: "Acme Corp",
  status: "active"
)

merchant2, api_key2 = Merchant.create_with_api_key(
  name: "Tech Startup Inc",
  status: "active"
)

puts "Merchant 1 API Key: #{api_key1}"
puts "Merchant 2 API Key: #{api_key2}"
puts "\n⚠️  IMPORTANT: Save these API keys - they won't be shown again!"

puts "\nCreating customers..."

customer1 = Customer.create!(
  merchant: merchant1,
  email: "john.doe@example.com",
  name: "John Doe"
)

customer2 = Customer.create!(
  merchant: merchant1,
  email: "jane.smith@example.com",
  name: "Jane Smith"
)

customer3 = Customer.create!(
  merchant: merchant2,
  email: "bob.wilson@example.com",
  name: "Bob Wilson"
)

puts "\nCreating payment methods..."

payment_method1 = PaymentMethod.create!(
  customer: customer1,
  method_type: "card",
  last4: "4242",
  brand: "Visa",
  exp_month: 12,
  exp_year: 2025
)

payment_method2 = PaymentMethod.create!(
  customer: customer2,
  method_type: "card",
  last4: "5555",
  brand: "Mastercard",
  exp_month: 6,
  exp_year: 2026
)

payment_method3 = PaymentMethod.create!(
  customer: customer3,
  method_type: "card",
  last4: "1234",
  brand: "Amex",
  exp_month: 3,
  exp_year: 2027
)

puts "\nCreating payment intents..."

intent1 = PaymentIntent.create!(
  merchant: merchant1,
  customer: customer1,
  payment_method: payment_method1,
  amount_cents: 5000,
  currency: "USD",
  status: "created",
  idempotency_key: "intent_001"
)

intent2 = PaymentIntent.create!(
  merchant: merchant1,
  customer: customer2,
  payment_method: payment_method2,
  amount_cents: 10000,
  currency: "USD",
  status: "authorized",
  idempotency_key: "intent_002"
)

intent3 = PaymentIntent.create!(
  merchant: merchant2,
  customer: customer3,
  payment_method: payment_method3,
  amount_cents: 2500,
  currency: "USD",
  status: "captured",
  idempotency_key: "intent_003"
)

puts "\nCreating transactions..."

transaction1 = Transaction.create!(
  payment_intent: intent2,
  kind: "authorize",
  status: "succeeded",
  amount_cents: 10000,
  processor_ref: "txn_auth_001"
)

transaction2 = Transaction.create!(
  payment_intent: intent3,
  kind: "authorize",
  status: "succeeded",
  amount_cents: 2500,
  processor_ref: "txn_auth_002"
)

transaction3 = Transaction.create!(
  payment_intent: intent3,
  kind: "capture",
  status: "succeeded",
  amount_cents: 2500,
  processor_ref: "txn_capture_001"
)

puts "\nCreating ledger entries..."

LedgerEntry.create!(
  merchant: merchant1,
  transaction: transaction1,
  entry_type: "charge",
  amount_cents: 10000,
  currency: "USD"
)

LedgerEntry.create!(
  merchant: merchant2,
  transaction: transaction2,
  entry_type: "charge",
  amount_cents: 2500,
  currency: "USD"
)

LedgerEntry.create!(
  merchant: merchant2,
  transaction: transaction3,
  entry_type: "charge",
  amount_cents: 2500,
  currency: "USD"
)

puts "\n✅ Seed data created successfully!"
puts "\nSummary:"
puts "  - Merchants: #{Merchant.count}"
puts "  - Customers: #{Customer.count}"
puts "  - Payment Methods: #{PaymentMethod.count}"
puts "  - Payment Intents: #{PaymentIntent.count}"
puts "  - Transactions: #{Transaction.count}"
puts "  - Ledger Entries: #{LedgerEntry.count}"
