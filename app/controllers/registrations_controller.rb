class RegistrationsController < ApplicationController
  skip_before_action :require_active_user

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    return render_form_error unless @user.save

    sign_in(@user)
    redirect_to root_path, notice: t("auth.registered", name: @user.name)
  rescue ActiveRecord::RecordNotUnique
    @user.errors.add(:email, t("auth.email_taken"))
    render_form_error
  end

  private

  def registration_params
    params.expect(user: %i[name email password])
  end
end
