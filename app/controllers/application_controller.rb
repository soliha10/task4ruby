class ApplicationController < ActionController::Base
  prepend_before_action :require_active_user

  rescue_from ActionController::InvalidAuthenticityToken do
    redirect_to login_path, alert: t("auth.session_expired")
  end

  helper_method :current_user

  private

  attr_reader :current_user

  def require_active_user
    @current_user = User.find_by(id: session[:user_id]) if session[:user_id]
    return deny_access(t(session[:user_id] ? "auth.account_missing" : "auth.login_required")) if current_user.nil?

    deny_access(t("auth.blocked")) if current_user.blocked?
  end

  def deny_access(message)
    reset_session
    return redirect_to(login_path, alert: message) unless request.format.json?

    flash[:alert] = message
    render json: { error: message, redirect: login_url }, status: :unauthorized
  end

  def sign_in(user)
    reset_session
    session[:user_id] = user.id
    user.update_column(:last_login_at, Time.current)
  end

  def render_form_error(template = :new)
    render template, status: :unprocessable_content
  end
end
