defmodule Lightning.Invocation.PolicyTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.User
  import Lightning.InvocationFixtures
  import Lightning.ProjectsFixtures
  import Lightning.AccountsFixtures
  import Lightning.WorkflowsFixtures
  import Lightning.JobsFixtures

  test "users can't list runs for project they aren't members of" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])
    other_project = project_fixture()

    assert :ok =
             Bodyguard.permit(
               Lightning.Invocation.Policy,
               :list_runs,
               user,
               project
             )

    assert {:error, :unauthorized} =
             Bodyguard.permit(
               Lightning.Invocation.Policy,
               :list_runs,
               user,
               other_project
             )
  end

  test "users can't read a runs for project they aren't members of" do
    user = user_fixture()
    project = project_fixture(project_users: [%{user_id: user.id}])
    job = job_fixture(workflow_id: workflow_fixture(project_id: project.id).id)
    run = run_fixture(job_id: job.id)

    assert :ok =
             Bodyguard.permit(
               Lightning.Invocation.Policy,
               :read_run,
               user,
               run
             )

    other_run = run_fixture()

    assert {:error, :unauthorized} =
             Bodyguard.permit(
               Lightning.Invocation.Policy,
               :read_run,
               user,
               other_run
             )
  end

  test "default is to deny access" do
    assert {:error, :unauthorized} =
             Bodyguard.permit(Lightning.Invocation.Policy, :index, %User{
               role: :user
             })
  end
end
