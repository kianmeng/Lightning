defmodule Lightning.Accounts do
  @moduledoc """
  The Accounts context.
  """

  use Oban.Worker,
    queue: :background,
    max_attempts: 1

  import Ecto.Query, warn: false
  alias Lightning.Repo

  require Logger

  alias Lightning.Accounts.{User, UserToken, UserNotifier}
  alias Lightning.Credentials
  alias Lightning.Projects

  @spec purge_user(id :: Ecto.UUID.t()) :: :ok
  def purge_user(id) do
    Logger.debug(fn ->
      # coveralls-ignore-start
      "Purging user ##{id}..."
      # coveralls-ignore-stop
    end)

    # Remove credentials
    Credentials.list_credentials_for_user(id)
    |> Enum.each(&Credentials.delete_credential/1)

    # Revoke access to projects
    Projects.get_projects_for_user(%User{id: id})
    |> Repo.preload(:project_users)
    |> Enum.each(fn p ->
      Projects.update_project(
        p,
        %{
          "project_users" => %{
            "0" => %{
              "delete" => "true",
              "user_id" => id,
              "id" =>
                Enum.find(p.project_users, fn pu -> pu.user_id == id end)
                |> Map.get(:id)
            }
          }
        }
      )
    end)

    User
    |> Repo.get(id)
    |> delete_user()

    Logger.debug(fn ->
      # coveralls-ignore-start
      "User ##{id} purged."
      # coveralls-ignore-stop
    end)

    :ok
  end

  @doc """
  Perform, when called with %{"type" => "purge_deleted"} will find users that are ready for permanent deletion and purge them.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "purge_deleted"}}) do
    users =
      Repo.all(
        from(u in User,
          where: u.scheduled_deletion <= ago(0, "second")
        )
      )

    :ok = Enum.each(users, fn u -> purge_user(u.id) end)

    {:ok, %{users_deleted: users}}
  end

  @doc """
  Returns the list of users.

  ## Examples

      iex> list_users()
      [%User{}, ...]

  """
  def list_users do
    Repo.all(User)
  end

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Registers a superuser.

  ## Examples
      iex> register_superuser(%{field: value})
      {:ok, %User{}}

      iex> register_superuser(%{field: bad_value})
      {:error, %Ecto.Changeset{}}
  """

  def register_superuser(attrs) do
    %User{}
    |> User.superuser_registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_superuser(%User{} = user, attrs \\ %{}) do
    User.superuser_registration_changeset(user, attrs)
  end

  @doc """
  Gets a user by email and password.

  ## Examples

      iex> get_user_by_email_and_password("foo@example.com", "correct_password")
      %User{}

      iex> get_user_by_email_and_password("foo@example.com", "invalid_password")
      nil

  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking user changes.

  ## Examples

      iex> change_user_registration(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs, hash_password: false)
  end

  def change_user_details(%User{} = user, attrs \\ %{}) do
    User.details_changeset(user, attrs)
  end

  def update_user_details(%User{} = user, attrs \\ %{}) do
    User.details_changeset(user, attrs)
    |> Repo.update()
  end

  ## Settings

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}) do
    User.email_changeset(user, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user scheduled_deletion.

  ## Examples

      iex> change_scheduled_deletion(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_scheduled_deletion(user, attrs \\ %{}) do
    User.scheduled_deletion_changeset(user, attrs)
  end

  @doc """
  Emulates that the email will change without actually changing
  it in the database.

  ## Examples

      iex> apply_user_email(user, "valid password", %{email: ...})
      {:ok, %User{}}role: :superuser
      iex> apply_user_email(user, "invalid password", %{email: ...})
      {:error, %Ecto.Changeset{}}

  """
  def apply_user_email(user, password, attrs) do
    user
    |> User.email_changeset(attrs)
    |> User.validate_current_password(password)
    |> Ecto.Changeset.apply_action(:update)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  The confirmed_at date is also updated to the current time.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    with {:ok, query} <-
           UserToken.verify_change_email_token_query(token, context),
         %UserToken{sent_to: email} <- Repo.one(query),
         {:ok, _} <- Repo.transaction(user_email_multi(user, email, context)) do
      :ok
    else
      _ -> :error
    end
  end

  defp user_email_multi(user, email, context) do
    changeset =
      user
      |> User.email_changeset(%{email: email})
      |> User.confirm_changeset()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, [context])
    )
  end

  @doc """
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_update_email_instructions(user, current_email, &Routes.user_update_email_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_update_email_instructions(
        %User{} = user,
        current_email,
        update_email_url_fun
      )
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)

    UserNotifier.deliver_update_email_instructions(
      user,
      update_email_url_fun.(encoded_token)
    )
  end

  @doc """
  Deletes a user.

  ## Examples

      iex> delete_user(user)
      {:ok, %User{}}

      iex> delete_user(user)
      {:error, %Ecto.Changeset{}}

  """
  def delete_user(%User{} = user) do
    Repo.delete(user)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.

  ## Examples

      iex> change_user_password(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_password(user, attrs \\ %{}) do
    User.password_changeset(user, attrs, hash_password: false)
  end

  @doc """
  Updates the user password.

  ## Examples

      iex> update_user_password(user, "valid password", %{password: ...})
      {:ok, %User{}}

      iex> update_user_password(user, "invalid password", %{password: ...})
      {:error, %Ecto.Changeset{}}

  """
  def update_user_password(user, password, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> User.validate_current_password(password)

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Given a user and a confirmation email, this function sets a scheduled deletion
  date 7 days in the future. Note that subsequent logins will be blocked for
  users pending deletion.
  """
  def schedule_user_deletion(user, email) do
    User.scheduled_deletion_changeset(user, %{
      "scheduled_deletion" => DateTime.utc_now() |> Timex.shift(days: 7),
      "scheduled_deletion_email" => email
    })
    |> Repo.update()
    |> case do
      {:ok, user} ->
        UserNotifier.send_deletion_notification_email(user)
        {:ok, user}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_token(user, "session")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_token_query(token, "session")
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_session_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "session"))
    :ok
  end

  ## Auth

  @doc """
  Generates an auth token.
  """
  def generate_auth_token(user) do
    {token, user_token} = UserToken.build_token(user, "auth")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Exchanges an auth token for a session token.

  The auth token is removed from the database if successful.
  """
  def exchange_auth_token(auth_token) do
    case get_user_by_auth_token(auth_token) do
      user = %User{} ->
        delete_auth_token(auth_token)
        generate_user_session_token(user)

      any ->
        any
    end
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_auth_token(token) do
    {:ok, query} = UserToken.verify_token_query(token, "auth")
    Repo.one(query)
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_auth_token(token) do
    Repo.delete_all(UserToken.token_and_context_query(token, "auth"))
    :ok
  end

  ## API

  @doc """
  Generates an API token for a user.
  """
  def generate_api_token(user) do
    {token, user_token} = UserToken.build_token(user, "api")
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_api_token(token) do
    {:ok, query} = UserToken.verify_token_query(token, "api")
    Repo.one(query)
  end

  ## Confirmation

  @doc """
  Delivers the confirmation email instructions to the given user.

  ## Examples

      iex> deliver_user_confirmation_instructions(user, &Routes.user_confirmation_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

      iex> deliver_user_confirmation_instructions(confirmed_user, &Routes.user_confirmation_url(conn, :edit, &1))
      {:error, :already_confirmed}

  """
  def deliver_user_confirmation_instructions(
        %User{} = user,
        confirmation_url_fun
      )
      when is_function(confirmation_url_fun, 1) do
    if user.confirmed_at do
      {:error, :already_confirmed}
    else
      {encoded_token, user_token} = UserToken.build_email_token(user, "confirm")
      Repo.insert!(user_token)

      UserNotifier.deliver_confirmation_instructions(
        user,
        confirmation_url_fun.(encoded_token)
      )
    end
  end

  @doc """
  Confirms a user by the given token.

  If the token matches, the user account is marked as confirmed
  and the token is deleted.
  """
  def confirm_user(token) do
    with {:ok, query} <- UserToken.verify_email_token_query(token, "confirm"),
         %User{} = user <- Repo.one(query),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, ["confirm"])
    )
  end

  ## Reset password

  @doc """
  Delivers the reset password email to the given user.

  ## Examples

      iex> deliver_user_reset_password_instructions(user, &Routes.user_reset_password_url(conn, :edit, &1))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_reset_password_instructions(
        %User{} = user,
        reset_password_url_fun
      )
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} =
      UserToken.build_email_token(user, "reset_password")

    Repo.insert!(user_token)

    UserNotifier.deliver_reset_password_instructions(
      user,
      reset_password_url_fun.(encoded_token)
    )
  end

  @doc """
  Gets the user by reset password token.

  ## Examples

      iex> get_user_by_reset_password_token("validtoken")
      %User{}

      iex> get_user_by_reset_password_token("invalidtoken")
      nil

  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <-
           UserToken.verify_email_token_query(token, "reset_password"),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.

  ## Examples

      iex> reset_user_password(user, %{password: "new long password", password_confirmation: "new long password"})
      {:ok, %User{}}

      iex> reset_user_password(user, %{password: "valid", password_confirmation: "not the same"})
      {:error, %Ecto.Changeset{}}

  """
  def reset_user_password(user, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.password_changeset(user, attrs))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.user_and_contexts_query(user, :all)
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  @doc """
  Used to determine if there is at least one Superuser in the system.
  This triggers the setup page on fresh installs.
  """
  @spec has_one_superuser?() :: boolean()
  def has_one_superuser?() do
    from(u in User, select: count(), where: u.role == :superuser)
    |> Repo.one() >= 1
  end
end
