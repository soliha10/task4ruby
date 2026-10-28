module UsersHelper
  COLUMN_LABELS = { "name" => "Name", "email" => "E-mail", "last_login_at" => "Last login", "status" => "Status" }.freeze
  TIMESTAMP_FORMAT = "%Y-%m-%d %H:%M:%S %Z".freeze
  BULK_ACTION_BUTTONS = [
    { title: "Block selected users", path: :block_users_path, method: "patch", icon: "lock-fill", style: "primary", label: "Block" },
    { title: "Unblock selected users", path: :unblock_users_path, method: "patch", icon: "unlock-fill", style: "primary", aria_label: "Unblock" },
    { title: "Delete selected users", path: :destroy_users_path, method: "delete", icon: "trash-fill", style: "danger", aria_label: "Delete" }
  ].freeze

  def last_login_cell(time)
    return tag.span("Never", class: "text-body-secondary") unless time

    relative = time.future? ? "in #{time_ago_in_words(time)}" : "#{time_ago_in_words(time)} ago"
    tag.span(relative, title: l(time, format: TIMESTAMP_FORMAT), data: { bs_toggle: "tooltip" })
  end

  def status_badge(user)
    style = user.active? ? "text-bg-success" : "text-bg-secondary"
    tag.span(user.status.capitalize, class: "badge #{style}")
  end

  def job_position_text(user)
    user.job_position.presence || "—"
  end

  def sort_headers(current_sort, current_dir)
    safe_join(User::TABLE_SORT_FIELDS.map do |field|
      tag.th(sort_header(COLUMN_LABELS.fetch(field), field, current_sort, current_dir), scope: "col")
    end)
  end

  def bulk_action_buttons
    safe_join(BULK_ACTION_BUTTONS.map { |button| bulk_action_button(**button) })
  end

  private

  def sort_header(label, field, current_sort, current_dir)
    active = field == current_sort
    next_dir = active && current_dir == "desc" ? "asc" : "desc"
    icon = active ? tag.i(class: "bi bi-caret-#{current_dir == 'desc' ? 'down' : 'up'}-fill ms-1") : "".html_safe
    link_to safe_join([ label, icon ]), root_path(sort: field, dir: next_dir),
            class: "link-body-emphasis text-decoration-none", data: { sort_field: field }
  end

  def bulk_action_button(title:, path:, method:, icon:, style:, label: nil, aria_label: nil)
    tag.span(class: "d-inline-block", tabindex: 0, data: { bs_toggle: "tooltip" }, title: title) do
      tag.button(type: "submit", form: "users-form", formaction: public_send(path), name: "_method", value: method,
                 class: "btn btn-outline-#{style} bulk-action", aria: { label: aria_label }, disabled: true) do
        safe_join([ tag.i(class: [ "bi bi-#{icon}", ("me-1" if label) ]), label ].compact)
      end
    end
  end
end
