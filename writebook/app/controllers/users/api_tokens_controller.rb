class Users::ApiTokensController < ApplicationController
  include UserScoped

  before_action :ensure_current_user

  def create
    @user.regenerate_api_token!
    redirect_to user_profile_path(@user), notice: "API token regenerated."
  end

  private
    def ensure_current_user
      head :forbidden unless @user == Current.user
    end
end
