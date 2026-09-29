class ApplicationController < ActionController::Base
  before_action :set_current_editor

  private
    # Stand-in for real authentication: a name kept in the session. Every
    # correction is attributed to it, whatever the client claims.
    def set_current_editor
      session[:editing_session] ||= SecureRandom.alphanumeric(10)
      Current.user_name = session[:user_name].presence || "anonymous"
      Current.editing_session = session[:editing_session]
    end
end
