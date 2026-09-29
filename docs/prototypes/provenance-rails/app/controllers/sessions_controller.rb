class SessionsController < ApplicationController
  def update
    session[:user_name] = params.expect(:user_name).to_s.strip.first(40)
    redirect_back_or_to root_path
  end
end
