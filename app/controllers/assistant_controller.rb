class AssistantController < ApplicationController
  HISTORY_LIMIT = 20

  def create
    render json: Assistant::Chat.new(user: current_user).reply(params[:message].to_s, history: history_params)
  end

  private

  def history_params
    Array(params[:history]).filter_map { |turn| history_turn(turn) }.last(HISTORY_LIMIT)
  end

  def history_turn(turn)
    return unless turn.is_a?(ActionController::Parameters)

    turn = turn.permit(:role, :text)
    { role: turn[:role], text: turn[:text].to_s } if turn[:text].present?
  end
end
