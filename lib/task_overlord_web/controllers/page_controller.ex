defmodule TaskOverlordWeb.PageController do
  use TaskOverlordWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
