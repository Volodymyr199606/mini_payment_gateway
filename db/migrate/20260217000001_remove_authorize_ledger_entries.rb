# frozen_string_literal: true

class RemoveAuthorizeLedgerEntries < ActiveRecord::Migration[7.1]
  def up
    # Remove ledger charge entries tied to authorize (not capture) transactions.
    # Authorize holds funds but does not settle; only capture creates real revenue.
    # This fixes double-counting where both auth and capture created charges.
    execute <<-SQL.squish
      DELETE FROM ledger_entries
      WHERE transaction_id IN (
        SELECT id FROM transactions WHERE kind = 'authorize'
      )
    SQL
  end

  def down
    # Cannot restore deleted rows; no-op. Run db:reset if you need seed data.
  end
end
