class SessionsController < ApplicationController
  skip_before_action :require_active_user, only: %i[new create]

  def new
  end

  def create
    user = User.find_by_login(params[:email])
    return reject_login(t("auth.invalid_credentials")) unless user&.authenticate(params[:password].to_s)
    return reject_login(t("auth.blocked")) if user.blocked?

    sign_in(user)
    redirect_to root_path, notice: t("auth.welcome_back", name: user.name)
  end

  def destroy
    reset_session
    redirect_to login_path, notice: t("auth.logged_out")
  end

  private

  def reject_login(message)
    flash.now[:alert] = message
    render_form_error
  end
end
