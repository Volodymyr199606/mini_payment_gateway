module Paginatable
  extend ActiveSupport::Concern

  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  private

  def paginate(collection)
    page = params[:page].to_i
    per_page = [params[:per_page].to_i, MAX_PER_PAGE].min
    per_page = DEFAULT_PER_PAGE if per_page.zero?

    page = 1 if page < 1

    paginated = collection.page(page).per(per_page)

    {
      data: paginated,
      meta: {
        page: paginated.current_page,
        per_page: paginated.limit_value,
        total: paginated.total_count,
        total_pages: paginated.total_pages
      }
    }
  end
end
