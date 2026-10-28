module ApplicationHelper
  FLASH_STYLES = { notice: "success", alert: "danger" }.freeze

  def flash_messages
    FLASH_STYLES.filter_map { |key, style| [ flash[key], style ] if flash[key].present? }
  end

  def user_initials(user)
    user.name.to_s.sub(/\A(mr|mrs|ms|miss|dr|prof)\.?\s+/i, "").split.first(2).map { |part| part[0] }.join.upcase.presence || "?"
  end

  def form_field(form, attribute, label, type, **options)
    errors = form.object ? form.object.errors.full_messages_for(attribute) : []
    tag.div(class: "mb-3") do
      safe_join([
        form.label(attribute, label, class: "form-label"),
        form.public_send(type, attribute, class: [ "form-control", ("is-invalid" if errors.any?) ], required: true, **options),
        (tag.div(errors.to_sentence, class: "invalid-feedback") if errors.any?)
      ].compact)
    end
  end
end
