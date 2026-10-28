class UsersController < ApplicationController
  def index
    @sort = User.table_sort_field(params[:sort])
    @dir = User.sort_direction(params[:dir])
    @users = User.sorted_by(@sort, @dir)
  end

  def block
    apply_bulk_action("block")
  end

  def unblock
    apply_bulk_action("unblock")
  end

  def destroy_selected
    apply_bulk_action("delete")
  end

  private

  def selected_ids
    Array(params[:ids]).map(&:to_i).uniq
  end

  def apply_bulk_action(action)
    ids = selected_ids
    return redirect_to(root_path, alert: t("users.none_selected")) if ids.empty?

    count = User.apply_bulk_action(action, ids)
    outcome = t("users.outcomes.#{action}")
    result = t("users.bulk_result", count: count, outcome: outcome)
    return redirect_to(root_path, notice: result) unless User.locks_out?(action, ids, current_user.id)

    reset_session
    redirect_to login_path, alert: t("users.self_lockout", result: result, outcome: outcome)
  end
end
