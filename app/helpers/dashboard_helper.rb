module DashboardHelper
  # Display label for current merchant (name or email).
  def merchant_display_label
    return "" unless current_merchant
    current_merchant.name.presence || current_merchant.email.presence || "Account"
  end

  # Avatar initials from merchant name (e.g. "John Doe" -> "JD"), fallback "VO".
  def merchant_avatar_initials
    return "VO" unless current_merchant
    name = current_merchant.name.to_s.strip
    if name.blank?
      email = current_merchant.email.to_s.strip
      return email.length >= 2 ? email[0, 2].upcase : "VO"
    end
    parts = name.split(/\s+/, 2)
    if parts.size >= 2
      (parts[0][0] + parts[1][0]).upcase
    else
      name.length >= 2 ? name[0, 2].upcase : name[0].upcase
    end
  end

  # Returns CSS class for active navigation tab.
  def tab_class(tab)
    active = case tab.to_sym
             when :overview then current_page?(dashboard_overview_path)
             when :transactions then current_page?(dashboard_transactions_path)
             when :payment_intents then request.path.match?(%r{/dashboard/payment_intents})
             when :ledger then current_page?(dashboard_ledger_index_path)
             when :webhooks then current_page?(dashboard_webhooks_path)
             else false
             end
    active ? "subnav-tab-active" : ""
  end

  alias_method :nav_tab_class, :tab_class
end
